package handlers

import (
	"context"
	"errors"
	"fmt"
	"sync/atomic"
	"testing"
	"time"
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

func TestEnrichPlaylistArtworkUsesSquareSearchResultAndKeepsOriginalID(t *testing.T) {
	tracks := []webTrack{{
		ID:                     "original-video-id",
		Title:                  "Tana",
		Artist:                 "Houari",
		Artwork:                "https://i.ytimg.com/vi/original-video-id/w400-h225.jpg",
		needsArtworkEnrichment: true,
	}}
	search := func(query string) (map[string]interface{}, error) {
		if query != "Tana Houari" {
			t.Fatalf("unexpected search query %q", query)
		}
		return searchResponse("different-search-id", "Tana", "Titre • Houari", "https://yt3.ggpht.com/official=s544-c-k-c0x00ffffff-no-rj", 544, 544), nil
	}

	result := enrichPlaylistArtwork(context.Background(), tracks, search, newPlaylistArtworkMemoryCache(), 4)
	if result[0].ID != "original-video-id" {
		t.Fatalf("search result replaced the playback ID: %q", result[0].ID)
	}
	if result[0].Artwork != "https://yt3.ggpht.com/official=s544-c-k-c0x00ffffff-no-rj" {
		t.Fatalf("expected official square artwork, got %q", result[0].Artwork)
	}
}

func TestEnrichPlaylistArtworkBoundsConcurrencyAndUsesCache(t *testing.T) {
	tracks := make([]webTrack, 12)
	for index := range tracks {
		tracks[index] = webTrack{
			ID:                     fmt.Sprintf("original-%02d", index),
			Title:                  fmt.Sprintf("Song %02d", index),
			Artist:                 "Artist",
			Artwork:                "https://example.com/video.jpg",
			needsArtworkEnrichment: true,
		}
	}
	cache := newPlaylistArtworkMemoryCache()
	var calls atomic.Int32
	var inFlight atomic.Int32
	var maxInFlight atomic.Int32
	search := func(query string) (map[string]interface{}, error) {
		calls.Add(1)
		current := inFlight.Add(1)
		for {
			maximum := maxInFlight.Load()
			if current <= maximum || maxInFlight.CompareAndSwap(maximum, current) {
				break
			}
		}
		defer inFlight.Add(-1)
		time.Sleep(5 * time.Millisecond)
		title := query[:len(query)-len(" Artist")]
		return searchResponse("search-id", title, "Titre • Artist", "https://yt3.ggpht.com/cover=s400", 400, 400), nil
	}

	first := enrichPlaylistArtwork(context.Background(), tracks, search, cache, 3)
	if maxInFlight.Load() > 3 {
		t.Fatalf("expected at most 3 searches in flight, saw %d", maxInFlight.Load())
	}
	if calls.Load() != 12 {
		t.Fatalf("expected one search per uncached track, got %d", calls.Load())
	}
	for _, track := range first {
		if track.Artwork != "https://yt3.ggpht.com/cover=s400" {
			t.Fatalf("track was not enriched: %#v", track)
		}
	}

	_ = enrichPlaylistArtwork(context.Background(), tracks, search, cache, 3)
	if calls.Load() != 12 {
		t.Fatalf("expected second load to use cache, got %d total searches", calls.Load())
	}
}

func TestEnrichPlaylistArtworkCachesFailureAndReturnsFallback(t *testing.T) {
	track := webTrack{
		ID:                     "original-id",
		Title:                  "Unavailable",
		Artist:                 "Artist",
		Artwork:                "https://i.ytimg.com/vi/original-id/hq720.jpg",
		needsArtworkEnrichment: true,
	}
	cache := newPlaylistArtworkMemoryCache()
	var calls atomic.Int32
	search := func(string) (map[string]interface{}, error) {
		calls.Add(1)
		return nil, errors.New("youtube unavailable")
	}

	first := enrichPlaylistArtwork(context.Background(), []webTrack{track}, search, cache, 2)
	second := enrichPlaylistArtwork(context.Background(), []webTrack{track}, search, cache, 2)
	if first[0].Artwork != track.Artwork || second[0].Artwork != track.Artwork {
		t.Fatal("failed enrichment must preserve the original video fallback")
	}
	if calls.Load() != 1 {
		t.Fatalf("expected negative cache to suppress repeated failures, got %d calls", calls.Load())
	}
}

func TestEnrichPlaylistArtworkHonorsDeadline(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Millisecond)
	defer cancel()
	track := webTrack{ID: "id", Title: "Slow", Artist: "Artist", Artwork: "fallback", needsArtworkEnrichment: true}
	started := time.Now()
	result := enrichPlaylistArtwork(ctx, []webTrack{track}, func(string) (map[string]interface{}, error) {
		time.Sleep(150 * time.Millisecond)
		return searchResponse("search-id", "Slow", "Titre • Artist", "https://yt3.ggpht.com/slow", 500, 500), nil
	}, newPlaylistArtworkMemoryCache(), 1)

	if elapsed := time.Since(started); elapsed > 80*time.Millisecond {
		t.Fatalf("enrichment blocked beyond its deadline: %s", elapsed)
	}
	if result[0].Artwork != "fallback" {
		t.Fatalf("deadline should preserve fallback, got %q", result[0].Artwork)
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
