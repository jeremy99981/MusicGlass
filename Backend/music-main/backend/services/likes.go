package services

import (
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/lib/pq"
)

var (
	ErrAlreadyLiked = errors.New("song already liked")
	ErrLikeNotFound = errors.New("like not found")
)

// Like représente un like d'un utilisateur sur une musique.
type Like struct {
	ID        int       `json:"id"`
	Song      Song      `json:"song"`
	IsPublic  bool      `json:"is_public"`
	CreatedAt time.Time `json:"created_at"`
}

// LikeService porte la logique métier liée aux likes de musiques.
type LikeService struct {
	db *sql.DB
}

func NewLikeService(db *sql.DB) *LikeService {
	return &LikeService{db: db}
}

// AddLike upserte la song (via upsertSong) puis insère le like (privé par défaut).
func (s *LikeService) AddLike(userID int, input SongInput) (*Like, error) {
	song, err := upsertSong(s.db, input)
	if err != nil {
		return nil, err
	}

	var like Like
	like.Song = *song
	err = s.db.QueryRow(`
		INSERT INTO user_likes (user_id, song_id, is_public)
		VALUES ($1, $2, FALSE)
		RETURNING id, is_public, created_at`,
		userID, song.ID,
	).Scan(&like.ID, &like.IsPublic, &like.CreatedAt)
	if err != nil {
		if pqErr, ok := err.(*pq.Error); ok && pqErr.Code == "23505" {
			return nil, ErrAlreadyLiked
		}
		return nil, fmt.Errorf("insert like: %w", err)
	}
	return &like, nil
}

// RemoveLike supprime un like en vérifiant l'appartenance à userID.
func (s *LikeService) RemoveLike(userID, likeID int) error {
	res, err := s.db.Exec(
		`DELETE FROM user_likes WHERE id = $1 AND user_id = $2`,
		likeID, userID,
	)
	if err != nil {
		return fmt.Errorf("delete like: %w", err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrLikeNotFound
	}
	return nil
}

// GetUserLikes retourne tous les likes d'un utilisateur, du plus récent au plus ancien.
func (s *LikeService) GetUserLikes(userID int) ([]Like, error) {
	rows, err := s.db.Query(`
		SELECT ul.id, ul.is_public, ul.created_at,
		       s.id, s.external_id, s.title, s.artist,
		       COALESCE(s.album, ''), COALESCE(s.cover_url, ''), COALESCE(s.duration_ms, 0)
		FROM user_likes ul
		JOIN songs s ON s.id = ul.song_id
		WHERE ul.user_id = $1
		ORDER BY ul.created_at DESC`,
		userID,
	)
	if err != nil {
		return nil, fmt.Errorf("query likes: %w", err)
	}
	defer rows.Close()

	likes := make([]Like, 0)
	for rows.Next() {
		var l Like
		if err := rows.Scan(
			&l.ID, &l.IsPublic, &l.CreatedAt,
			&l.Song.ID, &l.Song.ExternalID, &l.Song.Title, &l.Song.Artist,
			&l.Song.Album, &l.Song.CoverURL, &l.Song.DurationMs,
		); err != nil {
			return nil, fmt.Errorf("scan like: %w", err)
		}
		likes = append(likes, l)
	}
	return likes, rows.Err()
}

// SetLikeVisibility change la visibilité d'un like en vérifiant l'appartenance à userID.
func (s *LikeService) SetLikeVisibility(userID, likeID int, isPublic bool) (*Like, error) {
	var like Like
	err := s.db.QueryRow(`
		WITH updated AS (
			UPDATE user_likes SET is_public = $1
			WHERE id = $2 AND user_id = $3
			RETURNING id, is_public, created_at, song_id
		)
		SELECT u.id, u.is_public, u.created_at,
		       s.id, s.external_id, s.title, s.artist,
		       COALESCE(s.album, ''), COALESCE(s.cover_url, ''), COALESCE(s.duration_ms, 0)
		FROM updated u
		JOIN songs s ON s.id = u.song_id`,
		isPublic, likeID, userID,
	).Scan(
		&like.ID, &like.IsPublic, &like.CreatedAt,
		&like.Song.ID, &like.Song.ExternalID, &like.Song.Title, &like.Song.Artist,
		&like.Song.Album, &like.Song.CoverURL, &like.Song.DurationMs,
	)
	if err == sql.ErrNoRows {
		return nil, ErrLikeNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("update like visibility: %w", err)
	}
	return &like, nil
}
