package handlers

import (
	"encoding/json"
	"regexp"
	"strconv"
	"strings"
)

type artworkCandidate struct {
	url            string
	width          int
	height         int
	sourcePriority int
}

var artworkSizePattern = regexp.MustCompile(`=w(\d+)-h(\d+)`)

func thumbnailFrom(renderer map[string]interface{}, videoID string) string {
	candidates := thumbnailCandidatesFrom(renderer)
	if len(candidates) > 0 {
		best := candidates[0]
		bestScore := artworkScore(best)
		for _, candidate := range candidates[1:] {
			if score := artworkScore(candidate); score > bestScore {
				best, bestScore = candidate, score
			}
		}
		return best.url
	}
	if len(videoID) == 11 {
		return "https://i.ytimg.com/vi/" + videoID + "/hq720.jpg"
	}
	return ""
}

func thumbnailCandidatesFrom(renderer map[string]interface{}) []artworkCandidate {
	paths := []struct {
		value    interface{}
		priority int
	}{
		{valueAt(renderer, "thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"), 400},
		{valueAt(renderer, "thumbnailRenderer", "musicThumbnailRenderer", "thumbnail", "thumbnails"), 400},
		{valueAt(renderer, "thumbnail", "croppedSquareThumbnailRenderer", "thumbnail", "thumbnails"), 380},
		{valueAt(renderer, "thumbnailRenderer", "croppedSquareThumbnailRenderer", "thumbnail", "thumbnails"), 380},
		{valueAt(renderer, "foregroundThumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"), 360},
		{valueAt(renderer, "thumbnail", "thumbnails"), 100},
		{valueAt(renderer, "thumbnailRenderer", "thumbnail", "thumbnails"), 100},
	}
	candidates := make([]artworkCandidate, 0, 8)
	for _, path := range paths {
		thumbs, ok := path.value.([]interface{})
		if !ok {
			continue
		}
		for _, value := range thumbs {
			thumb, ok := value.(map[string]interface{})
			if !ok {
				continue
			}
			artworkURL, _ := thumb["url"].(string)
			if strings.HasPrefix(artworkURL, "//") {
				artworkURL = "https:" + artworkURL
			}
			if artworkURL == "" {
				continue
			}
			width, height := thumbnailDimensions(thumb, artworkURL)
			candidates = append(candidates, artworkCandidate{artworkURL, width, height, path.priority})
		}
	}
	return candidates
}

func thumbnailDimensions(thumb map[string]interface{}, artworkURL string) (int, int) {
	width, height := integerValue(thumb["width"]), integerValue(thumb["height"])
	if width > 0 && height > 0 {
		return width, height
	}
	if matches := artworkSizePattern.FindStringSubmatch(artworkURL); len(matches) == 3 {
		return positiveInteger(matches[1]), positiveInteger(matches[2])
	}
	videoSizes := map[string][2]int{
		"maxresdefault.jpg": {1280, 720},
		"hq720.jpg":         {1280, 720},
		"sddefault.jpg":     {640, 480},
		"hqdefault.jpg":     {480, 360},
		"mqdefault.jpg":     {320, 180},
		"default.jpg":       {120, 90},
	}
	for suffix, dimensions := range videoSizes {
		if strings.Contains(artworkURL, "/"+suffix) {
			return dimensions[0], dimensions[1]
		}
	}
	return width, height
}

func integerValue(value interface{}) int {
	switch typed := value.(type) {
	case int:
		return typed
	case float64:
		return int(typed)
	case json.Number:
		result, _ := strconv.Atoi(typed.String())
		return result
	case string:
		return positiveInteger(typed)
	default:
		return 0
	}
}

func artworkScore(candidate artworkCandidate) float64 {
	score := float64(candidate.sourcePriority * 100)
	if candidate.width > 0 && candidate.height > 0 {
		ratio := float64(candidate.width) / float64(candidate.height)
		delta := ratio - 1
		if delta < 0 {
			delta = -delta
		}
		switch {
		case delta <= 0.08:
			score += 1_000_000
		case delta <= 0.2:
			score += 500_000
		default:
			score -= 300_000
		}
		shortEdge := candidate.width
		if candidate.height < shortEdge {
			shortEdge = candidate.height
		}
		if shortEdge > 2000 {
			shortEdge = 2000
		}
		score += float64(shortEdge)
	} else if candidate.sourcePriority >= 300 {
		score += 350_000
	}
	if strings.Contains(candidate.url, "ytimg.com/vi/") || strings.Contains(candidate.url, "ytimg.com/vi_webp/") {
		score -= 800_000
	}
	return score
}

func valueAt(root map[string]interface{}, path ...string) interface{} {
	current := interface{}(root)
	for _, key := range path {
		asMap, ok := current.(map[string]interface{})
		if !ok {
			return nil
		}
		current = asMap[key]
	}
	return current
}
