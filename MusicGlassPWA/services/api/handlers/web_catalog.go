package handlers

import (
	"context"
	"net/http"
	"os"
	"strings"

	"github.com/gin-gonic/gin"
)

func (h *Handler) WebCatalogStatus(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"provider": "youtube", "status": "active", "browserDirectAccess": false})
}

func (h *Handler) WebCatalogHome(c *gin.Context) {
	res, err := h.youtube.Home(h.youtube.CachedVisitorData(os.Getenv("YOUTUBE_VISITOR_DATA")))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, res)
}

func (h *Handler) WebCatalogPlaylist(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "playlist id is required"})
		return
	}

	visitorData := h.youtube.CachedVisitorData(os.Getenv("YOUTUBE_VISITOR_DATA"))
	res, err := h.youtube.Playlist(id, visitorData)
	if err != nil {
		internalError(c, err)
		return
	}
	playlist := canonicalWebPlaylist(res)
	ctx, cancel := context.WithTimeout(c.Request.Context(), playlistArtworkEnrichmentTimeout)
	defer cancel()
	playlist.Tracks = enrichPlaylistArtwork(ctx, playlist.Tracks, func(query string) (map[string]interface{}, error) {
		return h.youtube.Search(query, "", visitorData)
	}, sharedPlaylistArtworkCache, playlistArtworkSearchConcurrency)
	playlist.Tracks = replaceVideoArtworkFallbacks(playlist.Tracks, playlist.Artwork)
	c.JSON(http.StatusOK, playlist)
}

func (h *Handler) WebCatalogSearch(c *gin.Context) {
	query := c.Query("q")
	if query == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing query"})
		return
	}
	res, err := h.youtube.Search(query, "", h.youtube.CachedVisitorData(os.Getenv("YOUTUBE_VISITOR_DATA")))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, res)
}

func (h *Handler) WebCatalogRadio(c *gin.Context) {
	trackID := c.Query("track_id")
	title := c.Query("title")
	artist := c.Query("artist")
	query := strings.TrimSpace(title + " " + artist)
	if query == "" && trackID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing radio seed"})
		return
	}
	if query == "" {
		query = trackID
	}

	visitorData := h.youtube.CachedVisitorData(os.Getenv("YOUTUBE_VISITOR_DATA"))
	res, err := h.youtube.Related(trackID, visitorData)
	tracks := []webTrack{}
	source := "youtube_music_next"
	if err == nil {
		tracks = extractWebTracks(res, trackID)
	}
	if len(tracks) == 0 {
		source = "search_fallback"
		fallbackQuery := strings.TrimSpace(artist)
		if fallbackQuery == "" {
			fallbackQuery = query
		}
		res, err = h.youtube.Search(fallbackQuery, "", visitorData)
		if err == nil {
			tracks = filterRadioFallbackTracks(extractWebTracks(res, trackID), artist)
		}
	}
	if err != nil {
		c.JSON(http.StatusOK, gin.H{
			"seed":   webTrack{ID: trackID, Title: title, Artist: artist, Accent: "#263443"},
			"tracks": []webTrack{},
			"source": "search_fallback",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"seed":   webTrack{ID: trackID, Title: title, Artist: artist, Accent: "#263443"},
		"tracks": tracks,
		"source": source,
	})
}

// A text search is only an emergency fallback. Restrict it to the seed artist
// so an ambiguous song title cannot turn the queue into an unrelated topic mix.
func filterRadioFallbackTracks(tracks []webTrack, seedArtist string) []webTrack {
	seedTokens := artistTokens(seedArtist)
	if len(seedTokens) == 0 {
		return tracks
	}

	filtered := make([]webTrack, 0, len(tracks))
	for _, track := range tracks {
		candidateTokens := artistTokens(track.Artist)
		matched := false
		for artist := range seedTokens {
			if candidateTokens[artist] {
				matched = true
				break
			}
		}
		if matched {
			filtered = append(filtered, track)
		}
	}
	return filtered
}
