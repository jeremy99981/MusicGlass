package handlers

import (
	"strconv"
	"strings"
)

type webTrack struct {
	ID                     string `json:"id"`
	Title                  string `json:"title"`
	Artist                 string `json:"artist"`
	Album                  string `json:"album"`
	Artwork                string `json:"artwork"`
	Duration               int    `json:"duration"`
	Accent                 string `json:"accent"`
	needsArtworkEnrichment bool
}

func isPlaybackFallbackMatch(candidateTitle, candidateArtist, originalTitle, originalArtist string) bool {
	candidateStem := titleStem(candidateTitle)
	originalStem := titleStem(originalTitle)
	if candidateStem == "" || originalStem == "" {
		return false
	}
	titleMatches := candidateStem == originalStem || strings.Contains(candidateStem, originalStem) || strings.Contains(originalStem, candidateStem)
	if !titleMatches {
		return false
	}
	candidateTokens := artistTokens(candidateArtist)
	originalTokens := artistTokens(originalArtist)
	if len(candidateTokens) == 0 || len(originalTokens) == 0 {
		return true
	}
	for token := range candidateTokens {
		if originalTokens[token] {
			return true
		}
	}
	return false
}

func titleStem(value string) string {
	value = strings.ToLower(value)
	cutIndexes := []int{
		strings.Index(value, "("),
		strings.Index(value, "["),
	}
	cutAt := -1
	for _, index := range cutIndexes {
		if index > 0 && (cutAt == -1 || index < cutAt) {
			cutAt = index
		}
	}
	if cutAt > 0 {
		value = value[:cutAt]
	}
	var builder strings.Builder
	lastSpace := false
	for _, r := range value {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			builder.WriteRune(r)
			lastSpace = false
			continue
		}
		if !lastSpace {
			builder.WriteRune(' ')
			lastSpace = true
		}
	}
	return strings.TrimSpace(builder.String())
}

func artistTokens(value string) map[string]bool {
	replacer := strings.NewReplacer(" feat. ", ",", " ft. ", ",", " avec ", ",", "&", ",", "•", ",", "·", ",", "/", ",", ";", ",", "|", ",")
	parts := strings.Split(replacer.Replace(strings.ToLower(value)), ",")
	tokens := map[string]bool{}
	for _, part := range parts {
		token := strings.TrimSpace(part)
		if token != "" {
			tokens[token] = true
		}
	}
	return tokens
}

func extractWebTracks(root map[string]interface{}, seedID string) []webTrack {
	renderers := findMapsNamed(root, "musicResponsiveListItemRenderer")
	const trackLimit = 36
	tracks := make([]webTrack, 0, trackLimit)
	seen := map[string]bool{}
	for _, renderer := range renderers {
		id := stringAt(renderer, "playlistItemData", "videoId")
		if id == "" {
			id = stringAt(renderer, "navigationItemData", "videoId")
		}
		if id == "" || id == seedID || seen[id] {
			continue
		}
		title := textFrom(renderer["title"])
		if title == "" {
			title = textAt(renderer, "flexColumns", "0", "musicResponsiveListItemFlexColumnRenderer", "text")
		}
		metadata := responsiveFlexColumnText(renderer, 1)
		artist := musicPageRunText(metadata, "MUSIC_PAGE_TYPE_ARTIST")
		album := musicPageRunText(metadata, "MUSIC_PAGE_TYPE_ALBUM")
		videoType := musicVideoType(renderer)
		if title == "" || !isReliableArtist(artist) || isRejectedMusicCandidate(title, textFrom(metadata)) ||
			(videoType != "MUSIC_VIDEO_TYPE_ATV" && videoType != "MUSIC_VIDEO_TYPE_OMV") {
			continue
		}
		seen[id] = true
		tracks = append(tracks, webTrack{
			ID:       id,
			Title:    title,
			Artist:   artist,
			Album:    album,
			Artwork:  thumbnailFrom(renderer, id),
			Duration: 0,
			Accent:   "#263443",
		})
		if len(tracks) >= trackLimit {
			break
		}
	}
	panelRenderers := findMapsNamed(root, "playlistPanelVideoRenderer")
	for _, renderer := range panelRenderers {
		if len(tracks) >= trackLimit {
			break
		}
		id, _ := renderer["videoId"].(string)
		if id == "" || id == seedID || seen[id] {
			continue
		}
		title := textFrom(renderer["title"])
		byline := renderer["shortBylineText"]
		artist := musicPageRunText(byline, "MUSIC_PAGE_TYPE_ARTIST")
		if artist == "" {
			artist = cleanArtistLabel(textFrom(byline))
		}
		if artist == "" {
			byline = renderer["longBylineText"]
			artist = musicPageRunText(byline, "MUSIC_PAGE_TYPE_ARTIST")
			if artist == "" {
				artist = cleanArtistLabel(textFrom(byline))
			}
		}
		if title == "" || !isReliableArtist(artist) || isRejectedPanelCandidate(title, textFrom(byline)) {
			continue
		}
		seen[id] = true
		tracks = append(tracks, webTrack{
			ID:       id,
			Title:    title,
			Artist:   artist,
			Artwork:  thumbnailFrom(renderer, id),
			Duration: durationSeconds(textFrom(renderer["lengthText"])),
			Accent:   "#263443",
		})
	}
	return tracks
}

func cleanArtistLabel(value string) string {
	parts := strings.Split(value, "•")
	artist := strings.TrimSpace(parts[0])
	if !isReliableArtist(artist) {
		return ""
	}
	return artist
}

func musicPageRunText(value interface{}, expectedPageType string) string {
	asMap, ok := value.(map[string]interface{})
	if !ok {
		return ""
	}
	runs, ok := asMap["runs"].([]interface{})
	if !ok {
		return ""
	}
	values := make([]string, 0, 2)
	for _, value := range runs {
		run, ok := value.(map[string]interface{})
		if !ok {
			continue
		}
		pageType := stringAt(run, "navigationEndpoint", "browseEndpoint", "browseEndpointContextSupportedConfigs", "browseEndpointContextMusicConfig", "pageType")
		text, _ := run["text"].(string)
		if pageType == expectedPageType && strings.TrimSpace(text) != "" {
			values = append(values, strings.TrimSpace(text))
		}
	}
	return strings.Join(values, ", ")
}

func responsiveFlexColumnText(renderer map[string]interface{}, index int) interface{} {
	columns, ok := renderer["flexColumns"].([]interface{})
	if !ok || index < 0 || index >= len(columns) {
		return nil
	}
	column, ok := columns[index].(map[string]interface{})
	if !ok {
		return nil
	}
	flexColumn, ok := column["musicResponsiveListItemFlexColumnRenderer"].(map[string]interface{})
	if !ok {
		return nil
	}
	return flexColumn["text"]
}

func musicVideoType(renderer map[string]interface{}) string {
	var found string
	var walk func(interface{})
	walk = func(value interface{}) {
		if found != "" {
			return
		}
		switch typed := value.(type) {
		case map[string]interface{}:
			if videoType, ok := typed["musicVideoType"].(string); ok {
				found = videoType
				return
			}
			for _, child := range typed {
				walk(child)
			}
		case []interface{}:
			for _, child := range typed {
				walk(child)
			}
		}
	}
	walk(renderer)
	return found
}

func isReliableArtist(value string) bool {
	artist := strings.TrimSpace(value)
	lower := strings.ToLower(artist)
	if artist == "" || durationSeconds(artist) > 0 || strings.Contains(lower, " vue") || strings.Contains(lower, " view") {
		return false
	}
	switch lower {
	case "titre", "song", "vidéo", "video", "profil", "profile", "playlist", "artiste", "artist",
		"podcast", "épisode", "episode", "paroles", "lyrics", "inconnu", "unknown":
		return false
	default:
		return true
	}
}

func isRejectedMusicCandidate(values ...string) bool {
	return hasRejectedMarker(values, []string{
		"podcast", "épisode", "episode", "livestream", "live", "paroles", "lyrics", "karaoké", "karaoke",
		"réaction", "reaction", "interview", "entretien", "1h",
	})
}

func isRejectedPanelCandidate(values ...string) bool {
	return hasRejectedMarker(values, []string{"podcast", "épisode", "episode", "livestream", "live"})
}

func hasRejectedMarker(values []string, rejected []string) bool {
	text := strings.ToLower(strings.Join(values, " "))
	if strings.Contains(text, "live stream") || strings.Contains(text, "en direct") ||
		strings.Contains(text, "1 heure") || strings.Contains(text, "1 hour") {
		return true
	}
	words := strings.FieldsFunc(text, func(char rune) bool {
		return !((char >= 'a' && char <= 'z') || (char >= '0' && char <= '9') || char >= 128)
	})
	for _, word := range words {
		for _, marker := range rejected {
			if word == marker {
				return true
			}
		}
	}
	return false
}

func durationSeconds(value string) int {
	parts := strings.Split(strings.TrimSpace(value), ":")
	if len(parts) < 2 || len(parts) > 3 {
		return 0
	}
	total := 0
	for _, part := range parts {
		number, err := strconv.Atoi(part)
		if err != nil {
			return 0
		}
		total = total*60 + number
	}
	return total
}

func positiveInteger(value string) int {
	number, err := strconv.Atoi(strings.TrimSpace(value))
	if err != nil || number <= 0 {
		return 0
	}
	return number
}

func findMapsNamed(root interface{}, name string) []map[string]interface{} {
	var out []map[string]interface{}
	var walk func(interface{})
	walk = func(value interface{}) {
		switch typed := value.(type) {
		case map[string]interface{}:
			for key, child := range typed {
				if key == name {
					if asMap, ok := child.(map[string]interface{}); ok {
						out = append(out, asMap)
					}
					continue
				}
				walk(child)
			}
		case []interface{}:
			for _, child := range typed {
				walk(child)
			}
		}
	}
	walk(root)
	return out
}

func textAt(root map[string]interface{}, path ...string) string {
	current := interface{}(root)
	for _, key := range path {
		if arr, ok := current.([]interface{}); ok {
			index, err := strconv.Atoi(key)
			if err == nil && index >= 0 && index < len(arr) {
				current = arr[index]
				continue
			}
			return ""
		}
		asMap, ok := current.(map[string]interface{})
		if !ok {
			return ""
		}
		current = asMap[key]
	}
	return textFrom(current)
}

func textFrom(value interface{}) string {
	asMap, ok := value.(map[string]interface{})
	if !ok {
		return ""
	}
	if simple, ok := asMap["simpleText"].(string); ok {
		return simple
	}
	runs, ok := asMap["runs"].([]interface{})
	if !ok {
		return ""
	}
	parts := make([]string, 0, len(runs))
	for _, run := range runs {
		if runMap, ok := run.(map[string]interface{}); ok {
			if text, ok := runMap["text"].(string); ok {
				parts = append(parts, text)
			}
		}
	}
	return strings.Join(parts, "")
}

func stringAt(root map[string]interface{}, path ...string) string {
	current := interface{}(root)
	for _, key := range path {
		asMap, ok := current.(map[string]interface{})
		if !ok {
			return ""
		}
		current = asMap[key]
	}
	if value, ok := current.(string); ok {
		return value
	}
	return ""
}
