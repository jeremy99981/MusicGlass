package services

import (
	"database/sql"
	"fmt"

	"app/sanitize"
)

// Song représente une musique dans le référentiel partagé.
type Song struct {
	ID         int    `json:"id"`
	ExternalID string `json:"external_id"`
	Title      string `json:"title"`
	Artist     string `json:"artist"`
	Album      string `json:"album,omitempty"`
	CoverURL   string `json:"cover_url,omitempty"`
	DurationMs int    `json:"duration_ms,omitempty"`
}

// SongInput est le seul type d'entrée pour toute opération portant sur une musique externe.
// Utilisé par LikeService.AddLike et PlaylistService.AddSong.
type SongInput struct {
	ExternalID string
	Title      string
	Artist     string
	Album      *string
	CoverURL   *string
	DurationMs *int
}

// upsertSong insère la musique dans le référentiel partagé ou met à jour ses métadonnées
// si elle existe déjà (identifiée par external_id). Fonction interne au package.
func upsertSong(db *sql.DB, input SongInput) (*Song, error) {
	var s Song
	err := db.QueryRow(`
		INSERT INTO songs (external_id, title, artist, album, cover_url, duration_ms)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (external_id) DO UPDATE
			SET title       = EXCLUDED.title,
			    artist      = EXCLUDED.artist,
			    album       = EXCLUDED.album,
			    cover_url   = EXCLUDED.cover_url,
			    duration_ms = EXCLUDED.duration_ms
		RETURNING id, external_id, title, artist,
		          COALESCE(album, ''), COALESCE(cover_url, ''), COALESCE(duration_ms, 0)`,
		sanitize.String(input.ExternalID),
		sanitize.Name(input.Title),
		sanitize.Name(input.Artist),
		input.Album, input.CoverURL, input.DurationMs,
	).Scan(&s.ID, &s.ExternalID, &s.Title, &s.Artist,
		&s.Album, &s.CoverURL, &s.DurationMs)
	if err != nil {
		return nil, fmt.Errorf("upsert song: %w", err)
	}
	return &s, nil
}
