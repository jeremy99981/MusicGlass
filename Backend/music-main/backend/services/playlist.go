package services

import (
	"database/sql"
	"errors"
	"fmt"
	"time"

	"app/sanitize"
)

var (
	ErrPlaylistNotFound  = errors.New("playlist not found")
	ErrSongAlreadyInList = errors.New("song already in playlist")
	ErrEntryNotFound     = errors.New("playlist entry not found")
)

// PlaylistSong représente une musique dans une playlist avec sa position.
type PlaylistSong struct {
	EntryID  int       `json:"entry_id"`
	Position int       `json:"position"`
	Song     Song      `json:"song"`
	AddedAt  time.Time `json:"added_at"`
}

// Playlist représente une playlist avec ses musiques.
type Playlist struct {
	ID          int            `json:"id"`
	Name        string         `json:"name"`
	Description string         `json:"description,omitempty"`
	IsPublic    bool           `json:"is_public"`
	Songs       []PlaylistSong `json:"songs"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
}

// PlaylistSummary représente une playlist sans ses musiques (pour le listing).
type PlaylistSummary struct {
	ID          int       `json:"id"`
	Name        string    `json:"name"`
	Description string    `json:"description,omitempty"`
	IsPublic    bool      `json:"is_public"`
	SongCount   int       `json:"song_count"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// CreatePlaylistInput contient les champs de création d'une playlist.
type CreatePlaylistInput struct {
	Name        string
	Description *string
}

// UpdatePlaylistInput contient les champs modifiables (pointeurs = champ optionnel).
type UpdatePlaylistInput struct {
	Name        *string
	Description *string
	IsPublic    *bool
}


// PlaylistService porte la logique métier liée aux playlists.
type PlaylistService struct {
	db *sql.DB
}

func NewPlaylistService(db *sql.DB) *PlaylistService {
	return &PlaylistService{db: db}
}

// Create crée une playlist privée vide pour l'utilisateur.
func (s *PlaylistService) Create(userID int, input CreatePlaylistInput) (*Playlist, error) {
	var desc *string
	if input.Description != nil {
		trimmed := sanitize.String(*input.Description)
		desc = &trimmed
	}

	var p Playlist
	err := s.db.QueryRow(`
		INSERT INTO playlists (user_id, name, description, is_public)
		VALUES ($1, $2, $3, FALSE)
		RETURNING id, name, COALESCE(description, ''), is_public, created_at, updated_at`,
		userID, sanitize.Name(input.Name), desc,
	).Scan(&p.ID, &p.Name, &p.Description, &p.IsPublic, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("create playlist: %w", err)
	}
	p.Songs = []PlaylistSong{}
	return &p, nil
}

// GetByID retourne la playlist et ses musiques.
// Vérifie l'appartenance à userID en SQL (défense en profondeur).
func (s *PlaylistService) GetByID(userID, playlistID int) (*Playlist, error) {
	var p Playlist
	err := s.db.QueryRow(`
		SELECT id, name, COALESCE(description, ''), is_public, created_at, updated_at
		FROM playlists
		WHERE id = $1 AND user_id = $2`,
		playlistID, userID,
	).Scan(&p.ID, &p.Name, &p.Description, &p.IsPublic, &p.CreatedAt, &p.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, ErrPlaylistNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("query playlist: %w", err)
	}

	rows, err := s.db.Query(`
		SELECT ps.id, ps.position, ps.added_at,
		       s.id, s.external_id, s.title, s.artist,
		       COALESCE(s.album, ''), COALESCE(s.cover_url, ''), COALESCE(s.duration_ms, 0)
		FROM playlist_songs ps
		JOIN songs s ON s.id = ps.song_id
		WHERE ps.playlist_id = $1
		ORDER BY ps.position ASC, ps.added_at ASC`,
		playlistID,
	)
	if err != nil {
		return nil, fmt.Errorf("query playlist songs: %w", err)
	}
	defer rows.Close()

	p.Songs = make([]PlaylistSong, 0)
	for rows.Next() {
		var ps PlaylistSong
		if err := rows.Scan(
			&ps.EntryID, &ps.Position, &ps.AddedAt,
			&ps.Song.ID, &ps.Song.ExternalID, &ps.Song.Title, &ps.Song.Artist,
			&ps.Song.Album, &ps.Song.CoverURL, &ps.Song.DurationMs,
		); err != nil {
			return nil, fmt.Errorf("scan playlist song: %w", err)
		}
		p.Songs = append(p.Songs, ps)
	}
	return &p, rows.Err()
}

// ListByUser retourne toutes les playlists d'un utilisateur avec le nombre de musiques.
func (s *PlaylistService) ListByUser(userID int) ([]PlaylistSummary, error) {
	rows, err := s.db.Query(`
		SELECT p.id, p.name, COALESCE(p.description, ''), p.is_public,
		       p.created_at, p.updated_at,
		       COUNT(ps.id) AS song_count
		FROM playlists p
		LEFT JOIN playlist_songs ps ON ps.playlist_id = p.id
		WHERE p.user_id = $1
		GROUP BY p.id
		ORDER BY p.created_at DESC`,
		userID,
	)
	if err != nil {
		return nil, fmt.Errorf("query playlists: %w", err)
	}
	defer rows.Close()

	summaries := make([]PlaylistSummary, 0)
	for rows.Next() {
		var ps PlaylistSummary
		if err := rows.Scan(
			&ps.ID, &ps.Name, &ps.Description, &ps.IsPublic,
			&ps.CreatedAt, &ps.UpdatedAt, &ps.SongCount,
		); err != nil {
			return nil, fmt.Errorf("scan playlist summary: %w", err)
		}
		summaries = append(summaries, ps)
	}
	return summaries, rows.Err()
}

// Update met à jour les champs fournis. Le queryBuilder garantit qu'aucune
// valeur utilisateur n'est interpolée dans le SQL (pas d'injection possible).
func (s *PlaylistService) Update(userID, playlistID int, input UpdatePlaylistInput) (*PlaylistSummary, error) {
	qb := newQueryBuilder()

	if input.Name != nil {
		qb.add("name", sanitize.Name(*input.Name))
	}
	if input.Description != nil {
		qb.add("description", sanitize.String(*input.Description))
	}
	if input.IsPublic != nil {
		qb.add("is_public", *input.IsPublic)
	}

	if qb.empty() {
		return nil, ErrNoFieldsToUpdate
	}

	qb.addLiteral("updated_at = NOW()")
	setClauses, args, idx := qb.build(playlistID, userID)

	query := fmt.Sprintf(`
		WITH updated AS (
			UPDATE playlists SET %s
			WHERE id = $%d AND user_id = $%d
			RETURNING id, name, description, is_public, created_at, updated_at
		)
		SELECT u.id, u.name, COALESCE(u.description, ''), u.is_public,
		       u.created_at, u.updated_at,
		       (SELECT COUNT(*) FROM playlist_songs WHERE playlist_id = u.id) AS song_count
		FROM updated u`,
		setClauses, idx, idx+1,
	)

	var p PlaylistSummary
	err := s.db.QueryRow(query, args...).Scan(
		&p.ID, &p.Name, &p.Description, &p.IsPublic,
		&p.CreatedAt, &p.UpdatedAt, &p.SongCount,
	)
	if err == sql.ErrNoRows {
		return nil, ErrPlaylistNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("update playlist: %w", err)
	}
	return &p, nil
}

// Delete supprime une playlist en vérifiant l'appartenance à userID.
func (s *PlaylistService) Delete(userID, playlistID int) error {
	res, err := s.db.Exec(
		`DELETE FROM playlists WHERE id = $1 AND user_id = $2`,
		playlistID, userID,
	)
	if err != nil {
		return fmt.Errorf("delete playlist: %w", err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrPlaylistNotFound
	}
	return nil
}

// AddSong upserte la song (via upsertSong) puis l'insère dans la playlist à la dernière position.
func (s *PlaylistService) AddSong(userID, playlistID int, input SongInput) (*PlaylistSong, error) {
	// Vérification d'appartenance avant toute écriture.
	var ownerID int
	err := s.db.QueryRow(
		`SELECT user_id FROM playlists WHERE id = $1`, playlistID,
	).Scan(&ownerID)
	if err == sql.ErrNoRows {
		return nil, ErrPlaylistNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("check playlist owner: %w", err)
	}
	if ownerID != userID {
		return nil, ErrPlaylistNotFound // volontairement générique
	}

	// Upsert dans le référentiel partagé de songs.
	song, err := upsertSong(s.db, input)
	if err != nil {
		return nil, err
	}

	// Insertion à la fin de la playlist (position = MAX + 1).
	var ps PlaylistSong
	ps.Song = *song
	err = s.db.QueryRow(`
		INSERT INTO playlist_songs (playlist_id, song_id, position)
		VALUES ($1, $2,
		        (SELECT COALESCE(MAX(position), 0) + 1 FROM playlist_songs WHERE playlist_id = $1))
		ON CONFLICT (playlist_id, song_id) DO NOTHING
		RETURNING id, position, added_at`,
		playlistID, song.ID,
	).Scan(&ps.EntryID, &ps.Position, &ps.AddedAt)
	if err == sql.ErrNoRows {
		return nil, ErrSongAlreadyInList
	}
	if err != nil {
		return nil, fmt.Errorf("insert playlist song: %w", err)
	}
	return &ps, nil
}

// RemoveSong supprime une entrée de playlist en vérifiant l'appartenance à userID.
func (s *PlaylistService) RemoveSong(userID, playlistID, entryID int) error {
	res, err := s.db.Exec(`
		DELETE FROM playlist_songs
		WHERE id = $1
		  AND playlist_id = $2
		  AND EXISTS (
		        SELECT 1 FROM playlists WHERE id = $2 AND user_id = $3
		      )`,
		entryID, playlistID, userID,
	)
	if err != nil {
		return fmt.Errorf("delete playlist song: %w", err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrEntryNotFound
	}
	return nil
}
