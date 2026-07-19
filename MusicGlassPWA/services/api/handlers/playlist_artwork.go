package handlers

import (
	"context"
	"strings"
	"sync"
	"time"
)

const (
	playlistArtworkSearchConcurrency = 4
	playlistArtworkPositiveTTL       = 6 * time.Hour
	playlistArtworkNegativeTTL       = 5 * time.Minute
	playlistArtworkEnrichmentTimeout = 4 * time.Second
)

type webPlaylist struct {
	Title    string     `json:"title"`
	Subtitle string     `json:"subtitle"`
	Artist   string     `json:"artist"`
	Artwork  string     `json:"artwork"`
	Tracks   []webTrack `json:"tracks"`
}

type playlistArtworkCacheEntry struct {
	url       string
	expiresAt time.Time
}

type playlistArtworkMemoryCache struct {
	mu      sync.Mutex
	entries map[string]playlistArtworkCacheEntry
	now     func() time.Time
}

func newPlaylistArtworkMemoryCache() *playlistArtworkMemoryCache {
	return &playlistArtworkMemoryCache{
		entries: map[string]playlistArtworkCacheEntry{},
		now:     time.Now,
	}
}

func (cache *playlistArtworkMemoryCache) get(key string) (string, bool) {
	cache.mu.Lock()
	defer cache.mu.Unlock()
	entry, ok := cache.entries[key]
	if !ok {
		return "", false
	}
	if !entry.expiresAt.After(cache.now()) {
		delete(cache.entries, key)
		return "", false
	}
	return entry.url, true
}

func (cache *playlistArtworkMemoryCache) set(key, artworkURL string) {
	ttl := playlistArtworkPositiveTTL
	if artworkURL == "" {
		ttl = playlistArtworkNegativeTTL
	}
	cache.mu.Lock()
	cache.entries[key] = playlistArtworkCacheEntry{url: artworkURL, expiresAt: cache.now().Add(ttl)}
	cache.mu.Unlock()
}

var sharedPlaylistArtworkCache = newPlaylistArtworkMemoryCache()
var playlistArtworkSearchLimiter = make(chan struct{}, playlistArtworkSearchConcurrency)

func canonicalWebPlaylist(root map[string]interface{}) webPlaylist {
	playlist := webPlaylist{Title: "Playlist", Tracks: extractPlaylistTracks(root)}
	headerNames := []string{
		"musicImmersiveHeaderRenderer",
		"musicResponsiveHeaderRenderer",
		"musicDetailHeaderRenderer",
		"musicEditablePlaylistDetailHeaderRenderer",
		"musicVisualHeaderRenderer",
	}
	for _, name := range headerNames {
		headers := findMapsNamed(root, name)
		if len(headers) == 0 {
			continue
		}
		header := headers[0]
		if title := textFrom(header["title"]); title != "" {
			playlist.Title = title
		}
		playlist.Subtitle = textFrom(header["subtitle"])
		playlist.Artist = textFrom(header["straplineTextOne"])
		playlist.Artwork = thumbnailFrom(header, "")
		break
	}
	if playlist.Artwork == "" && len(playlist.Tracks) > 0 {
		playlist.Artwork = playlist.Tracks[0].Artwork
	}
	return playlist
}

func extractPlaylistTracks(root map[string]interface{}) []webTrack {
	renderers := findMapsNamed(root, "musicResponsiveListItemRenderer")
	tracks := make([]webTrack, 0, len(renderers))
	seen := map[string]bool{}
	for _, renderer := range renderers {
		id := stringAt(renderer, "playlistItemData", "videoId")
		if id == "" {
			id = stringAt(renderer, "navigationItemData", "videoId")
		}
		if id == "" || seen[id] {
			continue
		}
		title := textFrom(renderer["title"])
		if title == "" {
			title = textAt(renderer, "flexColumns", "0", "musicResponsiveListItemFlexColumnRenderer", "text")
		}
		if title == "" {
			continue
		}
		metadata := textAt(renderer, "flexColumns", "1", "musicResponsiveListItemFlexColumnRenderer", "text")
		artist, album := trackArtistAndAlbum(metadata)
		artwork, hasSquare := squareThumbnailFrom(renderer)
		if !hasSquare {
			artwork = thumbnailFrom(renderer, id)
		}
		seen[id] = true
		tracks = append(tracks, webTrack{
			ID:                     id,
			Title:                  title,
			Artist:                 artist,
			Album:                  album,
			Artwork:                artwork,
			Duration:               durationFromRenderer(renderer, metadata),
			Accent:                 "#263443",
			needsArtworkEnrichment: !hasSquare,
		})
	}
	return tracks
}

func trackArtistAndAlbum(metadata string) (string, string) {
	parts := splitMetadata(metadata)
	if len(parts) > 0 && isTrackTypeLabel(parts[0]) {
		parts = parts[1:]
	}
	values := make([]string, 0, len(parts))
	for _, part := range parts {
		lower := strings.ToLower(part)
		if durationSeconds(part) > 0 || strings.Contains(lower, " vue") || strings.Contains(lower, " view") {
			continue
		}
		values = append(values, part)
	}
	artist, album := "", ""
	if len(values) > 0 {
		artist = values[0]
	}
	if len(values) > 1 {
		album = values[1]
	}
	return artist, album
}

func splitMetadata(value string) []string {
	raw := strings.FieldsFunc(value, func(char rune) bool { return char == '•' || char == '·' })
	parts := make([]string, 0, len(raw))
	for _, part := range raw {
		if trimmed := strings.TrimSpace(part); trimmed != "" {
			parts = append(parts, trimmed)
		}
	}
	return parts
}

func isTrackTypeLabel(value string) bool {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "titre", "song", "vidéo", "video":
		return true
	default:
		return false
	}
}

func durationFromMetadata(metadata string) int {
	for _, part := range splitMetadata(metadata) {
		if duration := durationSeconds(part); duration > 0 {
			return duration
		}
	}
	return 0
}

func durationFromRenderer(renderer map[string]interface{}, metadata string) int {
	if duration := durationFromMetadata(metadata); duration > 0 {
		return duration
	}
	fixedColumn := textAt(renderer, "fixedColumns", "0", "musicResponsiveListItemFixedColumnRenderer", "text")
	return durationFromMetadata(fixedColumn)
}

func squareThumbnailFrom(renderer map[string]interface{}) (string, bool) {
	var best artworkCandidate
	bestScore := -1.0
	for _, candidate := range thumbnailCandidatesFrom(renderer) {
		if candidate.width <= 0 || candidate.height <= 0 {
			continue
		}
		ratio := float64(candidate.width) / float64(candidate.height)
		delta := ratio - 1
		if delta < 0 {
			delta = -delta
		}
		if delta > 0.08 {
			continue
		}
		if score := artworkScore(candidate); score > bestScore {
			best, bestScore = candidate, score
		}
	}
	return best.url, bestScore >= 0
}

type playlistArtworkSearch func(query string) (map[string]interface{}, error)

type artworkEnrichmentJob struct {
	key     string
	query   string
	indexes []int
}

type artworkEnrichmentResult struct {
	key string
	url string
}

func enrichPlaylistArtwork(ctx context.Context, tracks []webTrack, search playlistArtworkSearch, cache *playlistArtworkMemoryCache, concurrency int) []webTrack {
	enriched := append([]webTrack(nil), tracks...)
	jobsByKey := map[string]*artworkEnrichmentJob{}
	for index := range enriched {
		track := &enriched[index]
		if !track.needsArtworkEnrichment {
			continue
		}
		key := artworkCacheKey(*track)
		if artworkURL, ok := cache.get(key); ok {
			if artworkURL != "" {
				track.Artwork = artworkURL
			}
			continue
		}
		if existing := jobsByKey[key]; existing != nil {
			existing.indexes = append(existing.indexes, index)
			continue
		}
		jobsByKey[key] = &artworkEnrichmentJob{
			key:     key,
			query:   strings.TrimSpace(track.Title + " " + track.Artist),
			indexes: []int{index},
		}
	}
	if len(jobsByKey) == 0 || search == nil {
		return enriched
	}
	if concurrency < 1 {
		concurrency = 1
	}
	if concurrency > len(jobsByKey) {
		concurrency = len(jobsByKey)
	}

	jobs := make(chan *artworkEnrichmentJob, len(jobsByKey))
	results := make(chan artworkEnrichmentResult, len(jobsByKey))
	for _, job := range jobsByKey {
		jobs <- job
	}
	close(jobs)

	for range concurrency {
		go func() {
			for {
				select {
				case <-ctx.Done():
					return
				case job, ok := <-jobs:
					if !ok {
						return
					}
					if ctx.Err() != nil {
						return
					}
					select {
					case <-ctx.Done():
						return
					case playlistArtworkSearchLimiter <- struct{}{}:
					}
					response, err := search(job.query)
					<-playlistArtworkSearchLimiter
					artworkURL := ""
					if err == nil {
						artworkURL = matchingSearchArtwork(response, enriched[job.indexes[0]])
					}
					cache.set(job.key, artworkURL)
					results <- artworkEnrichmentResult{key: job.key, url: artworkURL}
				}
			}
		}()
	}

	pending := len(jobsByKey)
	for pending > 0 {
		select {
		case <-ctx.Done():
			return enriched
		case result := <-results:
			pending--
			if result.url == "" {
				continue
			}
			for _, index := range jobsByKey[result.key].indexes {
				enriched[index].Artwork = result.url
			}
		}
	}
	return enriched
}

func replaceVideoArtworkFallbacks(tracks []webTrack, collectionArtwork string) []webTrack {
	if collectionArtwork == "" || isVideoThumbnailURL(collectionArtwork) {
		return tracks
	}
	cleaned := append([]webTrack(nil), tracks...)
	for index := range cleaned {
		if cleaned[index].Artwork == "" || isVideoThumbnailURL(cleaned[index].Artwork) {
			cleaned[index].Artwork = collectionArtwork
		}
	}
	return cleaned
}

func isVideoThumbnailURL(value string) bool {
	lower := strings.ToLower(value)
	return strings.Contains(lower, "ytimg.com/vi/") || strings.Contains(lower, "ytimg.com/vi_webp/")
}

func artworkCacheKey(track webTrack) string {
	return titleStem(track.Title) + "|" + strings.ToLower(strings.TrimSpace(track.Artist))
}

func matchingSearchArtwork(root map[string]interface{}, original webTrack) string {
	bestURL := ""
	bestScore := -1.0
	for _, renderer := range findMapsNamed(root, "musicResponsiveListItemRenderer") {
		title := textFrom(renderer["title"])
		if title == "" {
			title = textAt(renderer, "flexColumns", "0", "musicResponsiveListItemFlexColumnRenderer", "text")
		}
		metadata := textAt(renderer, "flexColumns", "1", "musicResponsiveListItemFlexColumnRenderer", "text")
		parts := splitMetadata(metadata)
		if len(parts) > 0 && !isTrackTypeLabel(parts[0]) {
			continue
		}
		artist, _ := trackArtistAndAlbum(metadata)
		if !isPlaybackFallbackMatch(title, artist, original.Title, original.Artist) {
			continue
		}
		artworkURL, ok := squareThumbnailFrom(renderer)
		if !ok {
			continue
		}
		score := 1.0
		if titleStem(title) == titleStem(original.Title) {
			score += 10
		}
		if strings.EqualFold(strings.TrimSpace(artist), strings.TrimSpace(original.Artist)) {
			score += 5
		}
		if score > bestScore {
			bestURL, bestScore = artworkURL, score
		}
	}
	return bestURL
}
