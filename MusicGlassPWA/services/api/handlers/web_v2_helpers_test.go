package handlers

import (
	"fmt"
	"net/url"
	"testing"
)

func TestAllowedArtworkURL(t *testing.T) {
	allowed, _ := url.Parse("https://yt3.googleusercontent.com/cover=w1200-h1200-l90-rj")
	if !isAllowedArtworkURL(allowed) {
		t.Fatal("expected Google artwork to be allowed")
	}
	for _, raw := range []string{
		"http://yt3.googleusercontent.com/cover.jpg",
		"https://googleusercontent.com.evil.example/cover.jpg",
		"https://127.0.0.1/private.jpg",
	} {
		value, _ := url.Parse(raw)
		if isAllowedArtworkURL(value) {
			t.Fatalf("expected artwork URL to be rejected: %s", raw)
		}
	}
}

func TestDurationSeconds(t *testing.T) {
	tests := map[string]int{
		"3:45":    225,
		"1:02:03": 3723,
		"invalid": 0,
		"":        0,
	}
	for value, expected := range tests {
		if got := durationSeconds(value); got != expected {
			t.Fatalf("durationSeconds(%q) = %d, expected %d", value, got, expected)
		}
	}
}

func TestCleanArtistLabel(t *testing.T) {
	if got := cleanArtistLabel("Orelsan • 118 M de vues"); got != "Orelsan" {
		t.Fatalf("expected artist without view count, got %q", got)
	}
	if got := cleanArtistLabel("5:46"); got != "" {
		t.Fatalf("duration must not be exposed as artist, got %q", got)
	}
}

func TestExtractWebTracksMapsPlaylistPanelVideo(t *testing.T) {
	payload := map[string]interface{}{
		"contents": map[string]interface{}{
			"playlistPanelVideoRenderer": map[string]interface{}{
				"videoId": "next-track",
				"title": map[string]interface{}{
					"runs": []interface{}{map[string]interface{}{"text": "End of Line"}},
				},
				"shortBylineText": map[string]interface{}{
					"runs": []interface{}{map[string]interface{}{"text": "Daft Punk"}},
				},
				"lengthText": map[string]interface{}{
					"simpleText": "2:37",
				},
				"thumbnail": map[string]interface{}{
					"thumbnails": []interface{}{map[string]interface{}{"url": "https://example.com/art.jpg"}},
				},
			},
		},
	}

	tracks := extractWebTracks(payload, "seed-track")
	if len(tracks) != 1 {
		t.Fatalf("expected one track, got %d", len(tracks))
	}
	track := tracks[0]
	if track.ID != "next-track" || track.Title != "End of Line" || track.Artist != "Daft Punk" {
		t.Fatalf("unexpected mapped track: %#v", track)
	}
	if track.Duration != 157 || track.Artwork != "https://example.com/art.jpg" {
		t.Fatalf("unexpected metadata: %#v", track)
	}
}

func TestExtractWebTracksUsesTypedArtistAndAlbumRuns(t *testing.T) {
	payload := map[string]interface{}{
		"contents": musicSearchRenderer(
			"ziak-track", "Fixette", "MUSIC_VIDEO_TYPE_ATV",
			[]interface{}{
				map[string]interface{}{"text": "Titre"},
				map[string]interface{}{"text": " • "},
				musicBrowseRun("Ziak", "MUSIC_PAGE_TYPE_ARTIST"),
				map[string]interface{}{"text": " • "},
				musicBrowseRun("Chrome", "MUSIC_PAGE_TYPE_ALBUM"),
			},
		),
	}

	tracks := extractWebTracks(payload, "seed-track")
	if len(tracks) != 1 {
		t.Fatalf("expected the typed song fixture, got %#v", tracks)
	}
	if tracks[0].Artist != "Ziak" || tracks[0].Album != "Chrome" {
		t.Fatalf("expected artist and album endpoint runs, got %#v", tracks[0])
	}
}

func TestExtractWebTracksRejectsVideoProfileAndNonMusicalSearchResults(t *testing.T) {
	fixtures := []interface{}{
		musicSearchRenderer("generic-video", "Clip officiel", "MUSIC_VIDEO_TYPE_OMV", []interface{}{
			map[string]interface{}{"text": "Vidéo"}, map[string]interface{}{"text": " • "}, map[string]interface{}{"text": "Profil"},
		}),
		musicSearchRenderer("profile", "Ziak", "MUSIC_VIDEO_TYPE_ATV", []interface{}{
			musicBrowseRun("Profil", "MUSIC_PAGE_TYPE_ARTIST"),
		}),
		musicSearchRenderer("podcast", "Le podcast de Ziak", "MUSIC_VIDEO_TYPE_ATV", []interface{}{
			musicBrowseRun("Ziak", "MUSIC_PAGE_TYPE_ARTIST"),
		}),
		musicSearchRenderer("live", "Ziak live", "MUSIC_VIDEO_TYPE_OMV", []interface{}{
			musicBrowseRun("Ziak", "MUSIC_PAGE_TYPE_ARTIST"),
		}),
		musicSearchRenderer("lyrics", "Ziak - Fixette lyrics", "MUSIC_VIDEO_TYPE_ATV", []interface{}{
			musicBrowseRun("Ziak", "MUSIC_PAGE_TYPE_ARTIST"),
		}),
		musicSearchRenderer("hour", "Ziak mix 1h", "MUSIC_VIDEO_TYPE_ATV", []interface{}{
			musicBrowseRun("Ziak", "MUSIC_PAGE_TYPE_ARTIST"),
		}),
		musicSearchRenderer("karaoke", "Fixette karaoke", "MUSIC_VIDEO_TYPE_ATV", []interface{}{
			musicBrowseRun("Ziak", "MUSIC_PAGE_TYPE_ARTIST"),
		}),
		musicSearchRenderer("reaction", "Reaction a Fixette", "MUSIC_VIDEO_TYPE_ATV", []interface{}{
			musicBrowseRun("Ziak", "MUSIC_PAGE_TYPE_ARTIST"),
		}),
		musicSearchRenderer("interview", "Interview Ziak", "MUSIC_VIDEO_TYPE_ATV", []interface{}{
			musicBrowseRun("Ziak", "MUSIC_PAGE_TYPE_ARTIST"),
		}),
		musicSearchRenderer("playlist", "Playlist Ziak", "MUSIC_VIDEO_TYPE_PLAYLIST", []interface{}{
			musicBrowseRun("Ziak", "MUSIC_PAGE_TYPE_ARTIST"),
		}),
	}

	tracks := extractWebTracks(map[string]interface{}{"contents": fixtures}, "seed-track")
	if len(tracks) != 0 {
		t.Fatalf("expected all non-musical/generic fixtures to be rejected, got %#v", tracks)
	}
}

func TestExtractWebTracksAcceptsReliableOMVAndRejectsBadPanels(t *testing.T) {
	payload := map[string]interface{}{"contents": []interface{}{
		musicSearchRenderer("official-video", "Fixette (Official Video)", "MUSIC_VIDEO_TYPE_OMV", []interface{}{
			musicBrowseRun("Ziak", "MUSIC_PAGE_TYPE_ARTIST"),
		}),
		playlistPanelRenderer("panel-track", "Another One", "Daft Punk"),
		playlistPanelRenderer("panel-live", "Festival live", "Daft Punk"),
		playlistPanelRenderer("panel-podcast", "Studio talk", "Music Podcast"),
	}}

	tracks := extractWebTracks(payload, "seed-track")
	if len(tracks) != 2 || tracks[0].ID != "official-video" || tracks[1].ID != "panel-track" {
		t.Fatalf("expected reliable OMV and normal panel track only, got %#v", tracks)
	}
}

func TestExtractWebTracksReturnsUpToThirtySixResults(t *testing.T) {
	contents := make([]interface{}, 0, 40)
	for index := 0; index < 40; index++ {
		contents = append(contents, musicSearchRenderer(
			fmt.Sprintf("track-%02d", index), fmt.Sprintf("Song %02d", index), "MUSIC_VIDEO_TYPE_ATV",
			[]interface{}{musicBrowseRun("Reliable Artist", "MUSIC_PAGE_TYPE_ARTIST")},
		))
	}
	fixture := contents[0].(map[string]interface{})["musicResponsiveListItemRenderer"].(map[string]interface{})
	metadata := responsiveFlexColumnText(fixture, 1)
	if got := musicPageRunText(metadata, "MUSIC_PAGE_TYPE_ARTIST"); got != "Reliable Artist" {
		t.Fatalf("fixture artist = %q", got)
	}
	if got := musicVideoType(fixture); got != "MUSIC_VIDEO_TYPE_ATV" {
		t.Fatalf("fixture video type = %q", got)
	}

	tracks := extractWebTracks(map[string]interface{}{"contents": contents}, "seed-track")
	if len(tracks) != 36 {
		t.Fatalf("expected 36 tracks, got %d", len(tracks))
	}
}

func TestFilterRadioFallbackTracksKeepsOnlySeedArtist(t *testing.T) {
	tracks := []webTrack{
		{ID: "same", Title: "Fixette", Artist: "Ziak"},
		{ID: "collab", Title: "Mauvais jour", Artist: "Ziak · Maes"},
		{ID: "meditation", Title: "Feng Shui Meditation", Artist: "Nature Sounds"},
	}

	filtered := filterRadioFallbackTracks(tracks, "Ziak")
	if len(filtered) != 2 || filtered[0].ID != "same" || filtered[1].ID != "collab" {
		t.Fatalf("expected only Ziak fallback tracks, got %#v", filtered)
	}
}

func musicSearchRenderer(id, title, videoType string, metadataRuns []interface{}) map[string]interface{} {
	return map[string]interface{}{
		"musicResponsiveListItemRenderer": map[string]interface{}{
			"playlistItemData": map[string]interface{}{"videoId": id},
			"flexColumns": []interface{}{
				map[string]interface{}{"musicResponsiveListItemFlexColumnRenderer": map[string]interface{}{"text": map[string]interface{}{"runs": []interface{}{map[string]interface{}{"text": title}}}}},
				map[string]interface{}{"musicResponsiveListItemFlexColumnRenderer": map[string]interface{}{"text": map[string]interface{}{"runs": metadataRuns}}},
			},
			"overlay": map[string]interface{}{
				"musicItemThumbnailOverlayRenderer": map[string]interface{}{
					"content": map[string]interface{}{
						"musicPlayButtonRenderer": map[string]interface{}{
							"playNavigationEndpoint": map[string]interface{}{
								"watchEndpoint": map[string]interface{}{
									"watchEndpointMusicSupportedConfigs": map[string]interface{}{
										"watchEndpointMusicConfig": map[string]interface{}{"musicVideoType": videoType},
									},
								},
							},
						},
					},
				},
			},
		},
	}
}

func musicBrowseRun(text, pageType string) map[string]interface{} {
	return map[string]interface{}{
		"text": text,
		"navigationEndpoint": map[string]interface{}{
			"browseEndpoint": map[string]interface{}{
				"browseEndpointContextSupportedConfigs": map[string]interface{}{
					"browseEndpointContextMusicConfig": map[string]interface{}{"pageType": pageType},
				},
			},
		},
	}
}

func playlistPanelRenderer(id, title, artist string) map[string]interface{} {
	return map[string]interface{}{
		"playlistPanelVideoRenderer": map[string]interface{}{
			"videoId":         id,
			"title":           map[string]interface{}{"runs": []interface{}{map[string]interface{}{"text": title}}},
			"shortBylineText": map[string]interface{}{"runs": []interface{}{map[string]interface{}{"text": artist}}},
		},
	}
}

func TestThumbnailFromPrefersOfficialSquareArtwork(t *testing.T) {
	renderer := map[string]interface{}{
		"thumbnail": map[string]interface{}{
			"musicThumbnailRenderer": map[string]interface{}{
				"thumbnail": map[string]interface{}{
					"thumbnails": []interface{}{
						map[string]interface{}{"url": "https://lh3.googleusercontent.com/cover=w60-h60-l90-rj", "width": float64(60), "height": float64(60)},
						map[string]interface{}{"url": "https://lh3.googleusercontent.com/cover=w544-h544-l90-rj", "width": float64(544), "height": float64(544)},
					},
				},
			},
			"thumbnails": []interface{}{
				map[string]interface{}{"url": "https://i.ytimg.com/vi/abcdefghijk/maxresdefault.jpg", "width": float64(1280), "height": float64(720)},
			},
		},
	}

	if got := thumbnailFrom(renderer, "abcdefghijk"); got != "https://lh3.googleusercontent.com/cover=w544-h544-l90-rj" {
		t.Fatalf("expected high-resolution square Music artwork, got %q", got)
	}
}

func TestThumbnailFromUsesVideoThumbnailOnlyAsLastCandidate(t *testing.T) {
	withSquare := map[string]interface{}{
		"thumbnail": map[string]interface{}{
			"thumbnails": []interface{}{
				map[string]interface{}{"url": "https://example.com/cover.jpg", "width": float64(600), "height": float64(600)},
				map[string]interface{}{"url": "https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg", "width": float64(1280), "height": float64(720)},
			},
		},
	}
	if got := thumbnailFrom(withSquare, "abcdefghijk"); got != "https://example.com/cover.jpg" {
		t.Fatalf("expected square candidate, got %q", got)
	}

	videoOnly := map[string]interface{}{
		"thumbnail": map[string]interface{}{
			"thumbnails": []interface{}{
				map[string]interface{}{"url": "//i.ytimg.com/vi/abcdefghijk/hqdefault.jpg", "width": float64(480), "height": float64(360)},
			},
		},
	}
	if got := thumbnailFrom(videoOnly, "abcdefghijk"); got != "https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg" {
		t.Fatalf("expected unchanged video fallback, got %q", got)
	}
}
