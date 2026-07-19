package services

import (
	"crypto/rand"
	"database/sql"
	"encoding/base32"
	"errors"
	"fmt"
	"strings"
	"time"
)

var (
	ErrSessionNotFound = errors.New("session not found")
	ErrNotSessionHost  = errors.New("not session host")
)

// ListenSession représente une session d'écoute stockée en base.
type ListenSession struct {
	ID        int       `json:"id"`
	HostID    int       `json:"host_id"`
	Code      string    `json:"code"`
	IsActive  bool      `json:"is_active"`
	CreatedAt time.Time `json:"created_at"`
}

// SessionService porte la logique métier des sessions d'écoute partagée.
type SessionService struct {
	db *sql.DB
}

func NewSessionService(db *sql.DB) *SessionService {
	return &SessionService{db: db}
}

// Create crée une nouvelle session active hébergée par hostID.
// Le code généré est unique (8 caractères alphanumériques majuscules).
func (s *SessionService) Create(hostID int) (*ListenSession, error) {
	code, err := generateSessionCode()
	if err != nil {
		return nil, err
	}

	var sess ListenSession
	err = s.db.QueryRow(`
		INSERT INTO listen_sessions (host_id, code, is_active)
		VALUES ($1, $2, TRUE)
		RETURNING id, host_id, code, is_active, created_at`,
		hostID, code,
	).Scan(&sess.ID, &sess.HostID, &sess.Code, &sess.IsActive, &sess.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("create session: %w", err)
	}
	return &sess, nil
}

// GetByCode retourne une session active par son code de jointure.
func (s *SessionService) GetByCode(code string) (*ListenSession, error) {
	var sess ListenSession
	err := s.db.QueryRow(`
		SELECT id, host_id, code, is_active, created_at
		FROM listen_sessions
		WHERE code = $1 AND is_active = TRUE`,
		strings.ToUpper(code),
	).Scan(&sess.ID, &sess.HostID, &sess.Code, &sess.IsActive, &sess.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, ErrSessionNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get session: %w", err)
	}
	return &sess, nil
}

// End marque la session comme inactive. Retourne ErrSessionNotFound si
// la session n'existe pas ou si hostID n'est pas l'hôte.
func (s *SessionService) End(hostID int, code string) error {
	res, err := s.db.Exec(`
		UPDATE listen_sessions SET is_active = FALSE
		WHERE code = $1 AND host_id = $2 AND is_active = TRUE`,
		strings.ToUpper(code), hostID,
	)
	if err != nil {
		return fmt.Errorf("end session: %w", err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrSessionNotFound
	}
	return nil
}

// generateSessionCode génère un code aléatoire de 8 caractères (A-Z2-7).
func generateSessionCode() (string, error) {
	b := make([]byte, 5)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("generate code: %w", err)
	}
	return base32.StdEncoding.EncodeToString(b)[:8], nil
}
