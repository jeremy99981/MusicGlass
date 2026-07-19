package services

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	urlPkg "net/url"
	"strings"
	"sync"
	"time"
)

type YouTubeService struct {
	client        *http.Client
	visitorMu     sync.RWMutex
	visitorData   string
	visitorExpiry time.Time
}

func NewYouTubeService() *YouTubeService {
	return &YouTubeService{
		client: &http.Client{
			Timeout: 15 * time.Second,
			Transport: &http.Transport{
				MaxIdleConns:        32,
				MaxIdleConnsPerHost: 12,
				IdleConnTimeout:     90 * time.Second,
			},
		},
	}
}

const ytBase = "https://music.youtube.com/youtubei/v1"

func (s *YouTubeService) webRemixContext(visitorData, dataSyncId string) map[string]interface{} {
	clientParams := map[string]interface{}{
		"clientName":    "WEB_REMIX",
		"clientVersion": "1.20260213.01.00",
		"hl":            "fr",
		"gl":            "FR",
	}
	if visitorData != "" {
		clientParams["visitorData"] = visitorData
	}

	ctx := map[string]interface{}{
		"client": clientParams,
	}

	if dataSyncId != "" {
		ctx["user"] = map[string]interface{}{
			"onBehalfOfUser": dataSyncId,
		}
	}

	return ctx
}

func (s *YouTubeService) setHeaders(req *http.Request, visitorData, cookieHeader, authHeader string) {
	req.Header.Set("User-Agent", "Mozilla/5.0")
	req.Header.Set("Origin", "https://music.youtube.com")
	req.Header.Set("X-Origin", "https://music.youtube.com")
	req.Header.Set("Referer", "https://music.youtube.com/")
	req.Header.Set("X-Goog-Api-Format-Version", "1")
	req.Header.Set("X-YouTube-Client-Name", "67")
	req.Header.Set("X-YouTube-Client-Version", "1.20260213.01.00")
	req.Header.Set("Content-Type", "application/json")

	if visitorData != "" {
		req.Header.Set("X-Goog-Visitor-Id", visitorData)
	}
	if cookieHeader != "" {
		req.Header.Set("Cookie", cookieHeader)
	}
	if authHeader != "" {
		req.Header.Set("Authorization", authHeader)
	}
}

func (s *YouTubeService) postJSON(endpoint string, payload map[string]interface{}, visitorData, cookieHeader, authHeader string) (map[string]interface{}, error) {
	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequest("POST", ytBase+endpoint, bytes.NewBuffer(bodyBytes))
	if err != nil {
		return nil, err
	}

	s.setHeaders(req, visitorData, cookieHeader, authHeader)

	res, err := s.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()

	if res.StatusCode != 200 {
		return nil, fmt.Errorf("youtube api error: status %d", res.StatusCode)
	}

	var result map[string]interface{}
	if err := json.NewDecoder(res.Body).Decode(&result); err != nil {
		return nil, err
	}
	s.rememberVisitorData(result)

	return result, nil
}

func (s *YouTubeService) rememberVisitorData(result map[string]interface{}) {
	responseContext, _ := result["responseContext"].(map[string]interface{})
	visitorData, _ := responseContext["visitorData"].(string)
	visitorData = strings.TrimSpace(visitorData)
	if visitorData == "" {
		return
	}
	s.visitorMu.Lock()
	s.visitorData = visitorData
	s.visitorExpiry = time.Now().Add(6 * time.Hour)
	s.visitorMu.Unlock()
}

func (s *YouTubeService) CachedVisitorData(configured string) string {
	if configured = strings.TrimSpace(configured); configured != "" {
		return configured
	}
	s.visitorMu.RLock()
	defer s.visitorMu.RUnlock()
	if s.visitorExpiry.After(time.Now()) {
		return s.visitorData
	}
	return ""
}

// BootstrapVisitorData mirrors Metrolist's anonymous InnerTube bootstrap.
// A failed bootstrap is harmless because public endpoints also accept no visitor ID.
func (s *YouTubeService) BootstrapVisitorData(configured string) string {
	if visitorData := s.CachedVisitorData(configured); visitorData != "" {
		return visitorData
	}
	_, _ = s.Home("")
	return s.CachedVisitorData(configured)
}

func (s *YouTubeService) Home(visitorData string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"context":  s.webRemixContext(visitorData, ""),
		"browseId": "FEmusic_home",
	}
	return s.postJSON("/browse?alt=json", payload, visitorData, "", "")
}

func (s *YouTubeService) Playlist(id, visitorData string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"context":  s.webRemixContext(visitorData, ""),
		"browseId": normalizeMusicBrowseID(id),
	}
	return s.postJSON("/browse?alt=json", payload, visitorData, "", "")
}

func normalizeMusicBrowseID(id string) string {
	id = strings.TrimSpace(id)
	if strings.HasPrefix(id, "VL") {
		return id
	}
	for _, prefix := range []string{"PL", "RD", "OLAK"} {
		if strings.HasPrefix(id, prefix) {
			return "VL" + id
		}
	}
	return id
}

func (s *YouTubeService) Search(query, params, visitorData string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"context": s.webRemixContext(visitorData, ""),
		"query":   query,
	}
	if params != "" {
		payload["params"] = params
	}
	return s.postJSON("/search?alt=json", payload, visitorData, "", "")
}

func (s *YouTubeService) Next(videoID, playlistID, visitorData string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"context": s.webRemixContext(visitorData, ""),
	}
	if videoID != "" {
		payload["videoId"] = videoID
	}
	if playlistID != "" {
		payload["playlistId"] = playlistID
	}
	return s.postJSON("/next?alt=json&prettyPrint=false", payload, visitorData, "", "")
}

func (s *YouTubeService) Related(videoID, visitorData string) (map[string]interface{}, error) {
	initial, err := s.Next(videoID, "", visitorData)
	if err != nil {
		return nil, err
	}
	playlistID := findAutomixPlaylistID(initial)
	if playlistID == "" {
		return initial, nil
	}
	return s.Next(videoID, playlistID, visitorData)
}

func findAutomixPlaylistID(root interface{}) string {
	switch value := root.(type) {
	case map[string]interface{}:
		if rawID, ok := value["playlistId"].(string); ok && strings.HasPrefix(rawID, "RD") {
			return rawID
		}
		for _, child := range value {
			if found := findAutomixPlaylistID(child); found != "" {
				return found
			}
		}
	case []interface{}:
		for _, child := range value {
			if found := findAutomixPlaylistID(child); found != "" {
				return found
			}
		}
	}
	return ""
}

func (s *YouTubeService) Player(videoId, visitorData, cookieHeader, authHeader string) (map[string]interface{}, error) {
	type playerClient struct {
		endpoint      string
		name          string
		version       string
		clientName    string
		userAgent     string
		extraClient   map[string]interface{}
		includeOrigin bool
	}

	clients := []playerClient{
		{
			endpoint:   ytBase + "/player?alt=json&prettyPrint=false",
			name:       "ANDROID_VR",
			version:    "1.43.32",
			clientName: "28",
			userAgent:  "com.google.android.apps.youtube.vr.oculus/1.43.32 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/107.0.5284.2)",
			extraClient: map[string]interface{}{
				"osName":      "Android",
				"osVersion":   "12",
				"deviceMake":  "Oculus",
				"deviceModel": "Quest 3",
			},
		},
		{
			endpoint:   ytBase + "/player?alt=json&prettyPrint=false",
			name:       "ANDROID",
			version:    "21.03.38",
			clientName: "3",
			userAgent:  "com.google.android.youtube/21.03.38 (Linux; U; Android 14) gzip",
			extraClient: map[string]interface{}{
				"osName":    "Android",
				"osVersion": "14",
			},
		},
		{
			endpoint:   ytBase + "/player?alt=json&prettyPrint=false",
			name:       "IOS",
			version:    "21.03.1",
			clientName: "5",
			userAgent:  "com.google.ios.youtube/21.03.1 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)",
			extraClient: map[string]interface{}{
				"osName":      "iOS",
				"osVersion":   "18.2.22C152",
				"deviceMake":  "Apple",
				"deviceModel": "iPhone16,2",
			},
		},
		{
			endpoint:      "https://www.youtube.com/youtubei/v1/player?alt=json&prettyPrint=false",
			name:          "TVHTML5_SIMPLY_EMBEDDED_PLAYER",
			version:       "2.0",
			clientName:    "85",
			userAgent:     "Mozilla/5.0",
			includeOrigin: true,
		},
	}

	var lastErr error
	for _, clientSpec := range clients {
		clientPayload := map[string]interface{}{
			"clientName":    clientSpec.name,
			"clientVersion": clientSpec.version,
		}
		for key, value := range clientSpec.extraClient {
			clientPayload[key] = value
		}
		if visitorData != "" {
			clientPayload["visitorData"] = visitorData
		}

		payload := map[string]interface{}{
			"context": map[string]interface{}{
				"client": clientPayload,
			},
			"videoId": videoId,
		}

		bodyBytes, err := json.Marshal(payload)
		if err != nil {
			return nil, err
		}

		req, err := http.NewRequest("POST", clientSpec.endpoint, bytes.NewBuffer(bodyBytes))
		if err != nil {
			return nil, err
		}

		req.Header.Set("User-Agent", clientSpec.userAgent)
		req.Header.Set("X-Goog-Api-Format-Version", "1")
		req.Header.Set("X-YouTube-Client-Name", clientSpec.clientName)
		req.Header.Set("X-YouTube-Client-Version", clientSpec.version)
		req.Header.Set("Content-Type", "application/json")
		if clientSpec.includeOrigin {
			req.Header.Set("Origin", "https://music.youtube.com")
			req.Header.Set("X-Origin", "https://music.youtube.com")
			req.Header.Set("Referer", "https://music.youtube.com/")
		}

		if visitorData != "" {
			req.Header.Set("X-Goog-Visitor-Id", visitorData)
		}
		if cookieHeader != "" {
			req.Header.Set("Cookie", cookieHeader)
		}
		if authHeader != "" {
			req.Header.Set("Authorization", authHeader)
		}

		res, err := s.client.Do(req)
		if err != nil {
			lastErr = err
			continue
		}

		bodyData, readErr := io.ReadAll(res.Body)
		res.Body.Close()
		if readErr != nil {
			lastErr = readErr
			continue
		}
		if res.StatusCode != 200 {
			lastErr = fmt.Errorf("youtube %s player api error: status %d", clientSpec.name, res.StatusCode)
			continue
		}

		var result map[string]interface{}
		if err := json.Unmarshal(bodyData, &result); err != nil {
			lastErr = err
			continue
		}
		s.rememberVisitorData(result)
		if _, err := s.ExtractAudioURL(result); err != nil {
			lastErr = fmt.Errorf("youtube %s player rejected: %w", clientSpec.name, err)
			continue
		}
		return result, nil
	}
	if lastErr != nil {
		return nil, lastErr
	}
	return nil, fmt.Errorf("youtube player returned no usable audio")
}

func (s *YouTubeService) ExtractAudioURL(res map[string]interface{}) (string, error) {
	streamingData, ok := res["streamingData"].(map[string]interface{})
	if !ok {
		return "", fmt.Errorf("no streamingData found")
	}

	var formats []interface{}
	if adaptiveFormats, ok := streamingData["adaptiveFormats"].([]interface{}); ok {
		formats = append(formats, adaptiveFormats...)
	}
	if basicFormats, ok := streamingData["formats"].([]interface{}); ok {
		formats = append(formats, basicFormats...)
	}

	var bestURL string
	var highestScore float64 = -1

	for _, f := range formats {
		format, ok := f.(map[string]interface{})
		if !ok {
			continue
		}

		mimeType, _ := format["mimeType"].(string)
		if !strings.Contains(mimeType, "audio/") {
			continue
		}

		bitrate, _ := format["bitrate"].(float64)
		// AAC in MP4 is the most reliable format for long-running playback and
		// seeking on iOS Safari. Prefer it over Opus/WebM, then choose quality.
		score := bitrate
		if strings.Contains(mimeType, "audio/mp4") {
			score += 1_000_000_000
		}
		if score > highestScore {
			if url, ok := format["url"].(string); ok && url != "" {
				highestScore = score
				bestURL = url
			} else if signatureCipher, ok := format["signatureCipher"].(string); ok && signatureCipher != "" {
				// Parse the signatureCipher query string
				// e.g. "s=...&url=...&sp=..."
				// If it requires deciphering ('s' is present), we can't easily play it without decipher logic.
				// But we try to extract the base url.
				parsedQuery, err := urlPkg.ParseQuery(signatureCipher)
				if err == nil {
					if parsedQuery.Has("s") {
						// Requires deciphering, skip this format
						continue
					}
					rawUrl := parsedQuery.Get("url")
					if rawUrl != "" {
						highestScore = score
						sig := parsedQuery.Get("sig")
						if sig == "" {
							sig = parsedQuery.Get("signature")
						}
						sp := parsedQuery.Get("sp")
						if sp == "" {
							sp = "signature"
						}

						if sig != "" {
							bestURL = rawUrl + "&" + sp + "=" + sig
						} else {
							bestURL = rawUrl
						}
					}
				}
			}
		}
	}

	if bestURL == "" {
		return "", fmt.Errorf("no suitable audio format found")
	}

	return bestURL, nil
}
