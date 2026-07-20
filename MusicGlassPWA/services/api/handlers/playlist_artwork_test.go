package handlers

import (
	"errors"
	"sync/atomic"
	"testing"
)

func TestCanonicalWebPlaylistExtractsTracksForArtworkEnrichment(t *testing.T) {
	payload := map[string]interface{}{
		"header": map[string]interface{}{
			"musicDetailHeaderRenderer": map[string]interface{}{
				"title": map[string]interface{}{"runs": []interface{}{map[string]interface{}{"text": "Mix Houari"}}},
			},
		},
		"contents": map[string]interface{}{
			"musicResponsiveListItemRenderer": playlistRenderer(
				"original-id", "Tana", "Houari • Album • 3:12",
				"https://i.ytimg.com/vi/original-id/w400-h225.jpg", 400, 225,
			),
		},
	}

	playlist := canonicalWebPlaylist(payload)
	if playlist.Title != "Mix Houari" || len(playlist.Tracks) != 1 {
		t.Fatalf("unexpected canonical playlist: %#v", playlist)
	}
	track := playlist.Tracks[0]
	if track.ID != "original-id" || track.Title != "Tana" || track.Artist != "Houari" || track.Album != "Album" || track.Duration != 192 {
		t.Fatalf("unexpected canonical track: %#v", track)
	}
	if !track.needsArtworkEnrichment {
		t.Fatal("expected the 400x225 video thumbnail to require enrichment")
	}
}

func TestResolveTrackArtworkUsesSquareSearchResult(t *testing.T) {
	track := webTrack{ID: "original-video-id", Title: "Tana", Artist: "Houari"}
	search := func(query string) (map[string]interface{}, error) {
		if query != "Tana Houari" {
			t.Fatalf("unexpected search query %q", query)
		}
		return searchResponse("different-search-id", "Tana", "Titre • Houari", "https://yt3.ggpht.com/official=s544-c-k-c0x00ffffff-no-rj", 544, 544), nil
	}

	artwork := resolveTrackArtwork(track, newPlaylistArtworkMemoryCache(), search)
	if artwork != "https://yt3.ggpht.com/official=s544-c-k-c0x00ffffff-no-rj" {
		t.Fatalf("expected official square artwork, got %q", artwork)
	}
}

func TestResolveTrackArtworkUsesCacheAndAvoidsSecondSearch(t *testing.T) {
	track := webTrack{Title: "Song", Artist: "Artist"}
	cache := newPlaylistArtworkMemoryCache()
	var calls atomic.Int32
	search := func(string) (map[string]interface{}, error) {
		calls.Add(1)
		return searchResponse("search-id", "Song", "Titre • Artist", "https://yt3.ggpht.com/cover=s400", 400, 400), nil
	}

	first := resolveTrackArtwork(track, cache, search)
	second := resolveTrackArtwork(track, cache, search)
	if first != "https://yt3.ggpht.com/cover=s400" || second != first {
		t.Fatalf("expected stable cached artwork, got %q then %q", first, second)
	}
	if calls.Load() != 1 {
		t.Fatalf("expected the cache to suppress the second search, got %d calls", calls.Load())
	}
}

func TestResolveTrackArtworkCachesFailure(t *testing.T) {
	track := webTrack{Title: "Unavailable", Artist: "Artist"}
	cache := newPlaylistArtworkMemoryCache()
	var calls atomic.Int32
	search := func(string) (map[string]interface{}, error) {
		calls.Add(1)
		return nil, errors.New("youtube unavailable")
	}

	if artwork := resolveTrackArtwork(track, cache, search); artwork != "" {
		t.Fatalf("failed resolution must return empty artwork, got %q", artwork)
	}
	_ = resolveTrackArtwork(track, cache, search)
	if calls.Load() != 1 {
		t.Fatalf("expected negative cache to suppress repeated failures, got %d calls", calls.Load())
	}
}

func TestMarkPendingArtworkFlagsMissesAndAppliesCacheHits(t *testing.T) {
	cache := newPlaylistArtworkMemoryCache()
	cache.set(artworkCacheKey(webTrack{Title: "Known", Artist: "Artist"}), "https://yt3.ggpht.com/known=s400")
	cache.set(artworkCacheKey(webTrack{Title: "NoArt", Artist: "Artist"}), "") // négatif

	tracks := []webTrack{
		{ID: "square", Title: "Square", Artist: "Artist", Artwork: "https://album=s544"}, // pas d'enrichissement requis
		{ID: "known", Title: "Known", Artist: "Artist", Artwork: "video.jpg", needsArtworkEnrichment: true},
		{ID: "noart", Title: "NoArt", Artist: "Artist", Artwork: "video.jpg", needsArtworkEnrichment: true},
		{ID: "miss", Title: "Miss", Artist: "Artist", Artwork: "video.jpg", needsArtworkEnrichment: true},
	}

	result := markPendingArtwork(tracks, cache)
	if result[0].ArtworkPending {
		t.Fatal("track with a square artwork must not be marked pending")
	}
	if result[1].ArtworkPending || result[1].Artwork != "https://yt3.ggpht.com/known=s400" {
		t.Fatalf("cache hit must be applied and not pending: %#v", result[1])
	}
	if result[2].ArtworkPending {
		t.Fatal("negatively cached track must not be marked pending")
	}
	if !result[3].ArtworkPending {
		t.Fatal("cache miss must be marked pending for on-demand resolution")
	}
	if tracks[3].ArtworkPending {
		t.Fatal("markPendingArtwork must not mutate the input slice")
	}
}

func TestReplaceVideoArtworkFallbacksUsesCollectionCover(t *testing.T) {
	collectionArtwork := "https://yt3.googleusercontent.com/playlist=w544-h544-l90-rj"
	tracks := []webTrack{
		{ID: "official", Artwork: "https://yt3.googleusercontent.com/album=w544-h544-l90-rj"},
		{ID: "video", Artwork: "https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg"},
		{ID: "missing"},
	}

	result := replaceVideoArtworkFallbacks(tracks, collectionArtwork)
	if result[0].Artwork != tracks[0].Artwork {
		t.Fatalf("official artwork must be preserved, got %q", result[0].Artwork)
	}
	if result[1].Artwork != collectionArtwork || result[2].Artwork != collectionArtwork {
		t.Fatalf("video and missing artworks must use the collection cover: %#v", result)
	}
	if tracks[1].Artwork == collectionArtwork {
		t.Fatal("fallback replacement must not mutate the input slice")
	}
}

func playlistRenderer(id, title, metadata, artworkURL string, width, height int) map[string]interface{} {
	return map[string]interface{}{
		"playlistItemData": map[string]interface{}{"videoId": id},
		"flexColumns": []interface{}{
			map[string]interface{}{"musicResponsiveListItemFlexColumnRenderer": map[string]interface{}{"text": map[string]interface{}{"runs": []interface{}{map[string]interface{}{"text": title}}}}},
			map[string]interface{}{"musicResponsiveListItemFlexColumnRenderer": map[string]interface{}{"text": map[string]interface{}{"runs": []interface{}{map[string]interface{}{"text": metadata}}}}},
		},
		"thumbnail": map[string]interface{}{
			"musicThumbnailRenderer": map[string]interface{}{
				"thumbnail": map[string]interface{}{
					"thumbnails": []interface{}{map[string]interface{}{"url": artworkURL, "width": float64(width), "height": float64(height)}},
				},
			},
		},
	}
}

func searchResponse(id, title, metadata, artworkURL string, width, height int) map[string]interface{} {
	return map[string]interface{}{
		"contents": map[string]interface{}{
			"musicResponsiveListItemRenderer": playlistRenderer(id, title, metadata, artworkURL, width, height),
		},
	}
}
