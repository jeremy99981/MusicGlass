package services

import (
	"testing"
	"time"
)

func TestExtractAudioURL(t *testing.T) {
	svc := NewYouTubeService()

	// 1. Mock payload without streamingData
	res1 := map[string]interface{}{}
	_, err := svc.ExtractAudioURL(res1)
	if err == nil {
		t.Errorf("Expected error for missing streamingData")
	}

	// 2. Mock payload with valid streamingData
	res2 := map[string]interface{}{
		"streamingData": map[string]interface{}{
			"adaptiveFormats": []interface{}{
				map[string]interface{}{
					"mimeType": "video/mp4; codecs=\"avc1.4d4015\"",
					"bitrate":  float64(300000),
					"url":      "http://example.com/video",
				},
				map[string]interface{}{
					"mimeType": "audio/mp4; codecs=\"mp4a.40.2\"",
					"bitrate":  float64(128000),
					"url":      "http://example.com/audio128",
				},
				map[string]interface{}{
					"mimeType": "audio/webm; codecs=\"opus\"",
					"bitrate":  float64(160000),
					"url":      "http://example.com/audio160",
				},
			},
		},
	}

	url, err := svc.ExtractAudioURL(res2)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	// MP4/AAC is preferred for reliable iOS Safari playback.
	if url != "http://example.com/audio128" {
		t.Errorf("Expected http://example.com/audio128, got %s", url)
	}
}

func TestVisitorDataCache(t *testing.T) {
	svc := NewYouTubeService()
	svc.rememberVisitorData(map[string]interface{}{
		"responseContext": map[string]interface{}{"visitorData": "visitor-123"},
	})

	if got := svc.CachedVisitorData(""); got != "visitor-123" {
		t.Fatalf("expected cached visitor data, got %q", got)
	}
	if got := svc.CachedVisitorData("configured-visitor"); got != "configured-visitor" {
		t.Fatalf("configured visitor data must take precedence, got %q", got)
	}

	svc.visitorMu.Lock()
	svc.visitorExpiry = time.Now().Add(-time.Second)
	svc.visitorMu.Unlock()
	if got := svc.CachedVisitorData(""); got != "" {
		t.Fatalf("expired visitor data should be ignored, got %q", got)
	}
}

func TestExtractAudioURLIgnoresCipherThatNeedsDeciphering(t *testing.T) {
	svc := NewYouTubeService()
	result := map[string]interface{}{
		"streamingData": map[string]interface{}{
			"adaptiveFormats": []interface{}{
				map[string]interface{}{
					"mimeType":        "audio/mp4",
					"bitrate":         float64(256000),
					"signatureCipher": "url=https%3A%2F%2Fexample.com%2Fciphered&s=encrypted&sp=sig",
				},
				map[string]interface{}{
					"mimeType": "audio/mp4",
					"bitrate":  float64(128000),
					"url":      "https://example.com/playable",
				},
			},
		},
	}

	got, err := svc.ExtractAudioURL(result)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "https://example.com/playable" {
		t.Fatalf("expected directly playable format, got %q", got)
	}
}

func TestFindAutomixPlaylistID(t *testing.T) {
	payload := map[string]interface{}{
		"contents": []interface{}{
			map[string]interface{}{
				"automixPreviewVideoRenderer": map[string]interface{}{
					"content": map[string]interface{}{
						"automixPlaylistVideoRenderer": map[string]interface{}{
							"navigationEndpoint": map[string]interface{}{
								"watchPlaylistEndpoint": map[string]interface{}{"playlistId": "RDAMVMtrack123"},
							},
						},
					},
				},
			},
		},
	}
	if got := findAutomixPlaylistID(payload); got != "RDAMVMtrack123" {
		t.Fatalf("expected automix playlist id, got %q", got)
	}
}

func TestNormalizeMusicBrowseID(t *testing.T) {
	tests := map[string]string{
		"PL123":        "VLPL123",
		"RDAMVM123":    "VLRDAMVM123",
		"OLAK5uy_123":  "VLOLAK5uy_123",
		"VLOLAK5uy_1":  "VLOLAK5uy_1",
		"UCartist123":  "UCartist123",
		"MPREalbum123": "MPREalbum123",
	}

	for input, expected := range tests {
		if got := normalizeMusicBrowseID(input); got != expected {
			t.Errorf("normalizeMusicBrowseID(%q) = %q, want %q", input, got, expected)
		}
	}
}
