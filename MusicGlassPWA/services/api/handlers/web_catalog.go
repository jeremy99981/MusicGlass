package handlers

import (
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

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

// playlistResponseTTL borne la durée de vie du cache de playlists canoniques.
// Il évite de refaire un appel réseau YouTube (~1,5s) à chaque re-clic ou retour
// arrière sur le même raccourci.
const playlistResponseTTL = 10 * time.Minute

var playlistResponseCache = struct {
	sync.RWMutex
	values map[string]playlistCacheEntry
}{values: map[string]playlistCacheEntry{}}

type playlistCacheEntry struct {
	playlist  webPlaylist
	expiresAt time.Time
}

func cachedCanonicalPlaylist(id string) (webPlaylist, bool) {
	playlistResponseCache.RLock()
	defer playlistResponseCache.RUnlock()
	entry, ok := playlistResponseCache.values[id]
	if !ok || time.Now().After(entry.expiresAt) {
		return webPlaylist{}, false
	}
	return entry.playlist, true
}

func storeCanonicalPlaylist(id string, playlist webPlaylist) {
	playlistResponseCache.Lock()
	defer playlistResponseCache.Unlock()
	playlistResponseCache.values[id] = playlistCacheEntry{playlist: playlist, expiresAt: time.Now().Add(playlistResponseTTL)}
}

func (h *Handler) WebCatalogPlaylist(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "playlist id is required"})
		return
	}

	playlist, cached := cachedCanonicalPlaylist(id)
	if !cached {
		res, err := h.youtube.Playlist(id, h.youtube.CachedVisitorData(os.Getenv("YOUTUBE_VISITOR_DATA")))
		if err != nil {
			internalError(c, err)
			return
		}
		playlist = canonicalWebPlaylist(res)
		storeCanonicalPlaylist(id, playlist)
	}

	// Réponse immédiate: on applique seulement les pochettes déjà en cache (aucun
	// appel réseau) et on marque ArtworkPending celles qui restent à résoudre. Le
	// front les résout à la demande (WebCatalogArtwork) pour les seules lignes qui
	// approchent du viewport — une playlist de 200 titres s'affiche donc instantanément.
	playlist.Tracks = markPendingArtwork(playlist.Tracks, sharedPlaylistArtworkCache)
	playlist.Tracks = replaceVideoArtworkFallbacks(playlist.Tracks, playlist.Artwork)
	c.JSON(http.StatusOK, playlist)
}

// WebCatalogArtwork résout la pochette carrée d'une seule piste (title+artist).
// Endpoint léger appelé par le front au défilement, avec limiteur global pour ne
// pas saturer YouTube. Le résultat (positif ou négatif) est mis en cache.
func (h *Handler) WebCatalogArtwork(c *gin.Context) {
	track := webTrack{Title: strings.TrimSpace(c.Query("title")), Artist: strings.TrimSpace(c.Query("artist"))}
	if track.Title == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing title"})
		return
	}
	search := func(query string) (map[string]interface{}, error) {
		playlistArtworkSearchLimiter <- struct{}{}
		defer func() { <-playlistArtworkSearchLimiter }()
		return h.youtube.Search(query, "", h.youtube.CachedVisitorData(os.Getenv("YOUTUBE_VISITOR_DATA")))
	}
	artworkURL := resolveTrackArtwork(track, sharedPlaylistArtworkCache, search)
	c.Header("Cache-Control", "public, max-age=86400")
	c.JSON(http.StatusOK, gin.H{"artwork": artworkURL})
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
