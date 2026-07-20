package handlers

import (
	"app/services"
	"context"
	"crypto/sha1"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/kkdai/youtube/v2"
)

type streamCacheEntry struct {
	URL             string
	MimeType        string
	Source          string
	DurationSeconds int
	ExpiresAt       time.Time
}

var streamCache = struct {
	sync.RWMutex
	values map[string]streamCacheEntry
}{values: map[string]streamCacheEntry{}}

// respondProviderCredentialsRequired renvoie la réponse 428 commune lorsque la
// résolution d'un flux échoue faute d'identifiants YouTube Music côté serveur.
func respondProviderCredentialsRequired(c *gin.Context) {
	c.JSON(http.StatusPreconditionRequired, gin.H{
		"error":   "provider_credentials_required",
		"message": "Connexion YouTube Music serveur requise: configurez YOUTUBE_COOKIE_HEADER côté backend.",
	})
}

func (h *Handler) WebMediaResolve(c *gin.Context) {
	trackID := c.Param("track_id")
	title := c.Query("title")
	artist := c.Query("artist")
	start := time.Now()
	resolvedID, entry, cached, err := h.resolvePlayableStream(trackID, title, artist)
	if err != nil {
		log.Printf("[WebMediaResolve] track_id=%s failed resolve_ms=%d err=%v", trackID, time.Since(start).Milliseconds(), err)
		if errors.Is(err, errYouTubeCredentialsRequired) {
			respondProviderCredentialsRequired(c)
			return
		}
		c.JSON(http.StatusBadGateway, gin.H{"error": "failed to resolve stream"})
		return
	}
	log.Printf("[WebMediaResolve] track_id=%s resolved_id=%s cached=%t resolve_ms=%d", trackID, resolvedID, cached, time.Since(start).Milliseconds())
	c.JSON(http.StatusOK, gin.H{
		"stream_url":         "/api/v2/media/stream/" + resolvedID,
		"resolved_track_id":  resolvedID,
		"cached":             cached,
		"expires_in_seconds": int(time.Until(entry.ExpiresAt).Seconds()),
		"upstream_mime_type": entry.MimeType,
		"resolver":           entry.Source,
		"duration_seconds":   entry.DurationSeconds,
	})
}

func (h *Handler) resolvePlayableStream(trackID, title, artist string) (string, streamCacheEntry, bool, error) {
	entry, cached, err := resolveStreamURL(trackID)
	if err == nil {
		return trackID, entry, cached, nil
	}

	query := strings.TrimSpace(title + " " + artist)
	if query == "" || query == trackID {
		return "", streamCacheEntry{}, false, err
	}

	res, searchErr := h.youtube.Search(query, "", h.youtube.CachedVisitorData(os.Getenv("YOUTUBE_VISITOR_DATA")))
	if searchErr != nil {
		return "", streamCacheEntry{}, false, err
	}
	tracks := extractWebTracks(res, trackID)
	for _, candidate := range tracks {
		if candidate.ID == "" || candidate.ID == trackID || !isPlaybackFallbackMatch(candidate.Title, candidate.Artist, title, artist) {
			continue
		}
		entry, cached, candidateErr := resolveStreamURL(candidate.ID)
		if candidateErr == nil {
			return candidate.ID, entry, cached, nil
		}
	}
	return "", streamCacheEntry{}, false, err
}

func (h *Handler) WebMediaStream(c *gin.Context) {
	trackID := c.Param("track_id")
	start := time.Now()
	entry, cached, err := resolveStreamURL(trackID)
	if err != nil {
		log.Printf("[WebMediaStream] track_id=%s failed resolve_ms=%d err=%v", trackID, time.Since(start).Milliseconds(), err)
		if errors.Is(err, errYouTubeCredentialsRequired) {
			respondProviderCredentialsRequired(c)
			return
		}
		c.JSON(http.StatusBadGateway, gin.H{"error": "failed to extract stream url"})
		return
	}

	upResp, err := requestAudioUpstream(c.Request.Context(), entry.URL, c.GetHeader("Range"))
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "upstream request failed"})
		return
	}
	if upResp.StatusCode == http.StatusForbidden || upResp.StatusCode == http.StatusGone || upResp.StatusCode == http.StatusNotFound {
		upResp.Body.Close()
		forgetStreamURL(trackID)
		freshEntry, _, resolveErr := resolveStreamURL(trackID)
		if resolveErr == nil {
			entry = freshEntry
			cached = false
			upResp, err = requestAudioUpstream(c.Request.Context(), entry.URL, c.GetHeader("Range"))
		}
		if resolveErr != nil || err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": "upstream refresh failed"})
			return
		}
	}
	defer upResp.Body.Close()
	firstByteMs := time.Since(start).Milliseconds()
	log.Printf("[WebMediaStream] track_id=%s cached=%t status=%d first_byte_ms=%d", trackID, cached, upResp.StatusCode, firstByteMs)

	// Relay relevant headers from the upstream response.
	if ct := upResp.Header.Get("Content-Type"); ct != "" {
		c.Header("Content-Type", ct)
	}
	if cl := upResp.Header.Get("Content-Length"); cl != "" {
		c.Header("Content-Length", cl)
	}
	if acceptRanges := upResp.Header.Get("Accept-Ranges"); acceptRanges != "" {
		c.Header("Accept-Ranges", acceptRanges)
	}
	// Range responses must never be reused for a different byte interval. In
	// particular, iOS frequently closes and reopens the media request on pause.
	c.Header("Cache-Control", "private, no-store, no-transform")
	c.Header("X-Content-Type-Options", "nosniff")
	if cr := upResp.Header.Get("Content-Range"); cr != "" {
		c.Header("Content-Range", cr)
	}

	// Use the upstream status code (200 for full body, 206 for partial content).
	c.Status(upResp.StatusCode)

	// Stream the audio bytes to the client.
	buffer := make([]byte, 64*1024)
	_, _ = io.CopyBuffer(c.Writer, upResp.Body, buffer)
}

var errYouTubeCredentialsRequired = errors.New("youtube provider credentials required")

var streamYouTubeService = services.NewYouTubeService()

var mediaHTTPClient = &http.Client{
	Transport: &http.Transport{
		MaxIdleConns:          64,
		MaxIdleConnsPerHost:   24,
		IdleConnTimeout:       90 * time.Second,
		ResponseHeaderTimeout: 15 * time.Second,
	},
}

var artworkHTTPClient = &http.Client{
	Timeout: 12 * time.Second,
	CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if len(via) >= 3 || !isAllowedArtworkURL(req.URL) {
			return http.ErrUseLastResponse
		}
		return nil
	},
}

func isAllowedArtworkURL(value *url.URL) bool {
	if value == nil || value.Scheme != "https" {
		return false
	}
	host := strings.ToLower(value.Hostname())
	for _, allowed := range []string{"googleusercontent.com", "ggpht.com", "ytimg.com", "i.scdn.co"} {
		if host == allowed || strings.HasSuffix(host, "."+allowed) {
			return true
		}
	}
	return false
}

func (h *Handler) WebMediaArtwork(c *gin.Context) {
	artworkURL, err := url.Parse(c.Query("url"))
	if err != nil || !isAllowedArtworkURL(artworkURL) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid artwork URL"})
		return
	}

	request, err := http.NewRequestWithContext(c.Request.Context(), http.MethodGet, artworkURL.String(), nil)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid artwork request"})
		return
	}
	request.Header.Set("Accept", "image/avif,image/webp,image/jpeg,image/png,image/*")
	request.Header.Set("User-Agent", "MusicGlass/1.0")

	response, err := artworkHTTPClient.Do(request)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "failed to fetch artwork"})
		return
	}
	defer response.Body.Close()
	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		c.JSON(http.StatusBadGateway, gin.H{"error": "artwork provider rejected the request"})
		return
	}
	contentType := response.Header.Get("Content-Type")
	if !strings.HasPrefix(contentType, "image/") {
		c.JSON(http.StatusBadGateway, gin.H{"error": "invalid artwork response"})
		return
	}

	c.Header("Content-Type", contentType)
	c.Header("Cache-Control", "public, max-age=86400, immutable")
	c.Header("X-Content-Type-Options", "nosniff")
	c.Status(http.StatusOK)
	_, _ = io.Copy(c.Writer, io.LimitReader(response.Body, 10<<20))
}

func requestAudioUpstream(ctx context.Context, streamURL, rangeHeader string) (*http.Response, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, streamURL, nil)
	if err != nil {
		return nil, err
	}
	request.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")
	if rangeHeader != "" {
		request.Header.Set("Range", rangeHeader)
	}
	return mediaHTTPClient.Do(request)
}

func resolveStreamURL(trackID string) (streamCacheEntry, bool, error) {
	now := time.Now()
	streamCache.RLock()
	if entry, ok := streamCache.values[trackID]; ok && entry.ExpiresAt.After(now.Add(2*time.Minute)) {
		streamCache.RUnlock()
		return entry, true, nil
	}
	streamCache.RUnlock()

	ytService := streamYouTubeService
	visitorData := ytService.BootstrapVisitorData(os.Getenv("YOUTUBE_VISITOR_DATA"))
	cookieHeader := os.Getenv("YOUTUBE_COOKIE_HEADER")
	authHeader := os.Getenv("YOUTUBE_AUTH_HEADER")
	if strings.TrimSpace(cookieHeader) != "" {
		if authHeader == "" {
			authHeader = youtubeSAPISIDHash(cookieHeader)
		}
	}
	if player, playerErr := ytService.Player(trackID, visitorData, cookieHeader, authHeader); playerErr == nil {
		if audioURL, extractErr := ytService.ExtractAudioURL(player); extractErr == nil && audioURL != "" {
			entry := streamCacheEntry{
				URL:             audioURL,
				MimeType:        "audio/mp4",
				Source:          "innertube",
				DurationSeconds: positiveInteger(stringAt(player, "videoDetails", "lengthSeconds")),
				ExpiresAt:       now.Add(45 * time.Minute),
			}
			streamCache.Lock()
			streamCache.values[trackID] = entry
			streamCache.Unlock()
			return entry, false, nil
		}
	}

	client := youtube.Client{}
	video, err := client.GetVideo(trackID)
	if err != nil {
		return streamCacheEntry{}, false, err
	}
	formats := video.Formats.WithAudioChannels()
	if len(formats) == 0 {
		return streamCacheEntry{}, false, errors.New("no audio formats found")
	}
	formats.Sort()
	bestFormat := formats[0]
	for _, format := range formats {
		if strings.HasPrefix(format.MimeType, "audio/") {
			bestFormat = format
			break
		}
	}
	audioURL, err := client.GetStreamURL(video, &bestFormat)
	if err != nil || audioURL == "" {
		return streamCacheEntry{}, false, errors.New("failed to extract stream url")
	}
	entry := streamCacheEntry{
		URL:             audioURL,
		MimeType:        bestFormat.MimeType,
		Source:          "youtube_fallback",
		DurationSeconds: int(video.Duration.Round(time.Second) / time.Second),
		ExpiresAt:       now.Add(45 * time.Minute),
	}
	streamCache.Lock()
	streamCache.values[trackID] = entry
	streamCache.Unlock()
	return entry, false, nil
}

func youtubeSAPISIDHash(cookieHeader string) string {
	sapisid := ""
	for _, part := range strings.Split(cookieHeader, ";") {
		trimmed := strings.TrimSpace(part)
		if strings.HasPrefix(trimmed, "SAPISID=") {
			sapisid = strings.TrimPrefix(trimmed, "SAPISID=")
			break
		}
		if strings.HasPrefix(trimmed, "__Secure-3PAPISID=") {
			sapisid = strings.TrimPrefix(trimmed, "__Secure-3PAPISID=")
			break
		}
	}
	if sapisid == "" {
		return ""
	}
	timestamp := time.Now().Unix()
	payload := []byte(fmt.Sprintf("%d %s https://music.youtube.com", timestamp, sapisid))
	sum := sha1.Sum(payload)
	return fmt.Sprintf("SAPISIDHASH %d_%s", timestamp, hex.EncodeToString(sum[:]))
}

func forgetStreamURL(trackID string) {
	streamCache.Lock()
	delete(streamCache.values, trackID)
	streamCache.Unlock()
}
