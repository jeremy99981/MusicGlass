package services

import (
	"database/sql"
	"fmt"
	"strings"
	"time"
)

const searchHistoryLimit = 20

type SearchHistoryEntry struct {
	ID         int64     `json:"id"`
	Query      string    `json:"query"`
	SearchedAt time.Time `json:"searched_at"`
}

type SearchHistoryService struct {
	db *sql.DB
}

func NewSearchHistoryService(db *sql.DB) *SearchHistoryService {
	return &SearchHistoryService{db: db}
}

func NormalizeSearchQuery(value string) string {
	query := strings.Join(strings.Fields(value), " ")
	runes := []rune(query)
	if len(runes) > 160 {
		query = string(runes[:160])
	}
	return query
}

func (s *SearchHistoryService) List(userID int) ([]SearchHistoryEntry, error) {
	rows, err := s.db.Query(`
		SELECT id, query, searched_at
		FROM search_history
		WHERE user_id = $1
		ORDER BY searched_at DESC
		LIMIT $2`, userID, searchHistoryLimit)
	if err != nil {
		return nil, fmt.Errorf("query search history: %w", err)
	}
	defer rows.Close()

	entries := make([]SearchHistoryEntry, 0, searchHistoryLimit)
	for rows.Next() {
		var entry SearchHistoryEntry
		if err := rows.Scan(&entry.ID, &entry.Query, &entry.SearchedAt); err != nil {
			return nil, fmt.Errorf("scan search history: %w", err)
		}
		entries = append(entries, entry)
	}
	return entries, rows.Err()
}

func (s *SearchHistoryService) Record(userID int, value string) (*SearchHistoryEntry, error) {
	query := NormalizeSearchQuery(value)
	if query == "" {
		return nil, fmt.Errorf("search query is empty")
	}

	tx, err := s.db.Begin()
	if err != nil {
		return nil, fmt.Errorf("begin search history: %w", err)
	}
	defer tx.Rollback()

	if _, err := tx.Exec(`DELETE FROM search_history WHERE user_id = $1 AND LOWER(query) = LOWER($2)`, userID, query); err != nil {
		return nil, fmt.Errorf("deduplicate search history: %w", err)
	}

	var entry SearchHistoryEntry
	if err := tx.QueryRow(`
		INSERT INTO search_history (user_id, query)
		VALUES ($1, $2)
		RETURNING id, query, searched_at`, userID, query).Scan(&entry.ID, &entry.Query, &entry.SearchedAt); err != nil {
		return nil, fmt.Errorf("insert search history: %w", err)
	}

	if _, err := tx.Exec(`
		DELETE FROM search_history
		WHERE user_id = $1 AND id NOT IN (
			SELECT id FROM search_history WHERE user_id = $1 ORDER BY searched_at DESC LIMIT $2
		)`, userID, searchHistoryLimit); err != nil {
		return nil, fmt.Errorf("trim search history: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("commit search history: %w", err)
	}
	return &entry, nil
}

func (s *SearchHistoryService) Clear(userID int) error {
	if _, err := s.db.Exec(`DELETE FROM search_history WHERE user_id = $1`, userID); err != nil {
		return fmt.Errorf("clear search history: %w", err)
	}
	return nil
}
