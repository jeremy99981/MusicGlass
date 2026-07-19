package db

import (
	"database/sql"
	"fmt"
	"os"

	_ "github.com/lib/pq"
)

// Connect ouvre et valide la connexion à PostgreSQL.
func Connect() (*sql.DB, error) {
	dsn := fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		os.Getenv("DB_HOST"),
		os.Getenv("DB_PORT"),
		os.Getenv("DB_USER"),
		os.Getenv("DB_PASSWORD"),
		os.Getenv("DB_NAME"),
	)

	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, fmt.Errorf("sql.Open: %w", err)
	}

	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("db.Ping: %w", err)
	}

	return db, nil
}

// Migrate applique toutes les migrations DDL de façon idempotente.
// Peut être appelé sur une base vierge comme sur une base existante.
func Migrate(db *sql.DB) error {
	stmts := []string{
		`CREATE TABLE IF NOT EXISTS users (
			id            SERIAL PRIMARY KEY,
			name          VARCHAR(255) NOT NULL,
			email         VARCHAR(255) NOT NULL UNIQUE,
			password_hash VARCHAR(255) NOT NULL,
			created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
		)`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS first_name VARCHAR(100)`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS last_name  VARCHAR(100)`,
		`CREATE TABLE IF NOT EXISTS refresh_tokens (
			id         SERIAL PRIMARY KEY,
			token_hash VARCHAR(128) NOT NULL UNIQUE,
			user_id    INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			expires_at TIMESTAMPTZ NOT NULL,
			revoked    BOOLEAN NOT NULL DEFAULT FALSE,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id ON refresh_tokens(user_id)`,
		`CREATE TABLE IF NOT EXISTS songs (
			id          SERIAL PRIMARY KEY,
			external_id VARCHAR(255) NOT NULL UNIQUE,
			title       VARCHAR(255) NOT NULL,
			artist      VARCHAR(255) NOT NULL,
			album       VARCHAR(255),
			cover_url   TEXT,
			duration_ms INT,
			created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE TABLE IF NOT EXISTS user_likes (
			id         SERIAL PRIMARY KEY,
			user_id    INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			song_id    INT NOT NULL REFERENCES songs(id) ON DELETE CASCADE,
			is_public  BOOLEAN NOT NULL DEFAULT FALSE,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			UNIQUE (user_id, song_id)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_user_likes_user_id ON user_likes(user_id)`,
		`CREATE INDEX IF NOT EXISTS idx_user_likes_song_id  ON user_likes(song_id)`,
		`CREATE TABLE IF NOT EXISTS playlists (
			id          SERIAL PRIMARY KEY,
			user_id     INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			name        VARCHAR(255) NOT NULL,
			description TEXT,
			is_public   BOOLEAN NOT NULL DEFAULT FALSE,
			created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_playlists_user_id ON playlists(user_id)`,
		`CREATE TABLE IF NOT EXISTS playlist_songs (
			id          SERIAL PRIMARY KEY,
			playlist_id INT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
			song_id     INT NOT NULL REFERENCES songs(id)     ON DELETE CASCADE,
			position    INT NOT NULL DEFAULT 0,
			added_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			UNIQUE (playlist_id, song_id)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_playlist_songs_playlist ON playlist_songs(playlist_id)`,

		// ── Système d'amis ────────────────────────────────────────────────────
		`CREATE TABLE IF NOT EXISTS friendships (
			id           SERIAL PRIMARY KEY,
			requester_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			addressee_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			status       VARCHAR(10) NOT NULL DEFAULT 'pending',
			created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			UNIQUE(requester_id, addressee_id),
			CHECK(requester_id != addressee_id)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_friendships_requester ON friendships(requester_id)`,
		`CREATE INDEX IF NOT EXISTS idx_friendships_addressee ON friendships(addressee_id)`,

		// ── Sessions d'écoute partagée ────────────────────────────────────────
		`CREATE TABLE IF NOT EXISTS listen_sessions (
			id         SERIAL PRIMARY KEY,
			host_id    INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			code       VARCHAR(8) NOT NULL UNIQUE,
			is_active  BOOLEAN NOT NULL DEFAULT TRUE,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_listen_sessions_host ON listen_sessions(host_id)`,
		`CREATE INDEX IF NOT EXISTS idx_listen_sessions_code ON listen_sessions(code)`,
	}

	for _, stmt := range stmts {
		if _, err := db.Exec(stmt); err != nil {
			return fmt.Errorf("migrate: %w", err)
		}
	}
	return nil
}
