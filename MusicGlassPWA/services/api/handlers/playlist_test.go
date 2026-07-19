package handlers

import (
	"net/http"
	"testing"
	"time"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
)

// ── GET /users/:user_id/playlists ─────────────────────────────────────────────

func TestListPlaylists_Empty(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("LEFT JOIN playlist_songs").
		WillReturnRows(mock.NewRows([]string{
			"id", "name", "description", "is_public", "created_at", "updated_at", "song_count",
		}))

	r := newRouter(db)
	w := do(t, r, http.MethodGet, "/users/1/playlists", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusOK)
}

func TestListPlaylists_WithData(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("LEFT JOIN playlist_songs").
		WillReturnRows(mock.NewRows([]string{
			"id", "name", "description", "is_public", "created_at", "updated_at", "song_count",
		}).
			AddRow(1, "Playlist A", "", false, time.Now(), time.Now(), 3).
			AddRow(2, "Playlist B", "desc", true, time.Now(), time.Now(), 0))

	r := newRouter(db)
	w := do(t, r, http.MethodGet, "/users/1/playlists", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusOK)
}

// ── POST /users/:user_id/playlists ────────────────────────────────────────────

func TestCreatePlaylist_Success(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("INSERT INTO playlists").
		WillReturnRows(playlistRow(mock))

	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/playlists",
		`{"name":"Ma playlist"}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusCreated)
}

func TestCreatePlaylist_WithDescription(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("INSERT INTO playlists").
		WillReturnRows(mock.NewRows([]string{"id", "name", "description", "is_public", "created_at", "updated_at"}).
			AddRow(1, "Ma playlist", "Pour se détendre", false, time.Now(), time.Now()))

	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/playlists",
		`{"name":"Ma playlist","description":"Pour se détendre"}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusCreated)
}

func TestCreatePlaylist_MissingName(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/playlists", `{}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusBadRequest)
}

func TestCreatePlaylist_EmptyBody(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/playlists", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusBadRequest)
}

// ── GET /users/:user_id/playlists/:playlist_id ────────────────────────────────

func TestGetPlaylist_Success(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("FROM playlists WHERE id").
		WillReturnRows(playlistRow(mock))
	mock.ExpectQuery("FROM playlist_songs ps").
		WillReturnRows(mock.NewRows([]string{
			"id", "position", "added_at",
			"song_id", "external_id", "title", "artist", "album", "cover_url", "duration_ms",
		}))

	r := newRouter(db)
	w := do(t, r, http.MethodGet, "/users/1/playlists/1", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusOK)
}

func TestGetPlaylist_WithSongs(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("FROM playlists WHERE id").
		WillReturnRows(playlistRow(mock))
	mock.ExpectQuery("FROM playlist_songs ps").
		WillReturnRows(mock.NewRows([]string{
			"id", "position", "added_at",
			"song_id", "external_id", "title", "artist", "album", "cover_url", "duration_ms",
		}).AddRow(1, 1, time.Now(), 10, "sp:abc123", "Never Gonna Give You Up", "Rick Astley", "", "", 213000))

	r := newRouter(db)
	w := do(t, r, http.MethodGet, "/users/1/playlists/1", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusOK)
}

func TestGetPlaylist_NotFound(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("FROM playlists WHERE id").
		WillReturnRows(mock.NewRows([]string{
			"id", "name", "description", "is_public", "created_at", "updated_at",
		})) // aucune ligne

	r := newRouter(db)
	w := do(t, r, http.MethodGet, "/users/1/playlists/999", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusNotFound)
}

func TestGetPlaylist_InvalidID(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodGet, "/users/1/playlists/notanid", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusBadRequest)
}

// ── PATCH /users/:user_id/playlists/:playlist_id ──────────────────────────────

func TestUpdatePlaylist_Success(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("UPDATE playlists SET").
		WillReturnRows(playlistSummaryRow(mock))

	r := newRouter(db)
	w := do(t, r, http.MethodPatch, "/users/1/playlists/1",
		`{"name":"Nouveau nom"}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusOK)
}

func TestUpdatePlaylist_Visibility(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("UPDATE playlists SET").
		WillReturnRows(mock.NewRows([]string{"id", "name", "description", "is_public", "created_at", "updated_at", "song_count"}).
			AddRow(1, "Ma playlist", "", true, time.Now(), time.Now(), 0))

	r := newRouter(db)
	w := do(t, r, http.MethodPatch, "/users/1/playlists/1",
		`{"is_public":true}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusOK)
}

func TestUpdatePlaylist_NoFields(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPatch, "/users/1/playlists/1",
		`{}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusBadRequest)
}

func TestUpdatePlaylist_NotFound(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("UPDATE playlists SET").
		WillReturnRows(mock.NewRows([]string{
			"id", "name", "description", "is_public", "created_at", "updated_at", "song_count",
		})) // aucune ligne → ErrPlaylistNotFound

	r := newRouter(db)
	w := do(t, r, http.MethodPatch, "/users/1/playlists/999",
		`{"name":"x"}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusNotFound)
}

// ── DELETE /users/:user_id/playlists/:playlist_id ─────────────────────────────

func TestDeletePlaylist_Success(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectExec("DELETE FROM playlists").
		WillReturnResult(sqlmock.NewResult(0, 1))

	r := newRouter(db)
	w := do(t, r, http.MethodDelete, "/users/1/playlists/1", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusNoContent)
}

func TestDeletePlaylist_NotFound(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectExec("DELETE FROM playlists").
		WillReturnResult(sqlmock.NewResult(0, 0)) // 0 lignes supprimées

	r := newRouter(db)
	w := do(t, r, http.MethodDelete, "/users/1/playlists/999", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusNotFound)
}

func TestDeletePlaylist_InvalidID(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodDelete, "/users/1/playlists/notanid", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusBadRequest)
}

// ── POST /users/:user_id/playlists/:playlist_id/songs ─────────────────────────

func TestAddSongToPlaylist_Success(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	// 1. Vérification propriétaire
	mock.ExpectQuery("SELECT user_id FROM playlists").
		WillReturnRows(mock.NewRows([]string{"user_id"}).AddRow(1))
	// 2. upsertSong
	mock.ExpectQuery("INSERT INTO songs").WillReturnRows(songRow(mock))
	// 3. Insertion dans playlist
	mock.ExpectQuery("INSERT INTO playlist_songs").
		WillReturnRows(mock.NewRows([]string{"id", "position", "added_at"}).
			AddRow(1, 1, time.Now()))

	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/playlists/1/songs",
		testSongBody, bearerToken(t, 1))
	assertStatus(t, w, http.StatusCreated)
}

func TestAddSongToPlaylist_PlaylistNotFound(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("SELECT user_id FROM playlists").
		WillReturnRows(mock.NewRows([]string{"user_id"})) // aucune ligne

	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/playlists/999/songs",
		testSongBody, bearerToken(t, 1))
	assertStatus(t, w, http.StatusNotFound)
}

func TestAddSongToPlaylist_PlaylistOwnedByOther(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	// La playlist existe mais appartient à user 2, pas user 1
	mock.ExpectQuery("SELECT user_id FROM playlists").
		WillReturnRows(mock.NewRows([]string{"user_id"}).AddRow(2))

	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/playlists/1/songs",
		testSongBody, bearerToken(t, 1))
	assertStatus(t, w, http.StatusNotFound) // volontairement opaque (pas de 403 pour éviter l'énumération)
}

func TestAddSongToPlaylist_AlreadyInPlaylist(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("SELECT user_id FROM playlists").
		WillReturnRows(mock.NewRows([]string{"user_id"}).AddRow(1))
	mock.ExpectQuery("INSERT INTO songs").WillReturnRows(songRow(mock))
	mock.ExpectQuery("INSERT INTO playlist_songs").
		WillReturnRows(mock.NewRows([]string{"id", "position", "added_at"})) // ON CONFLICT DO NOTHING → 0 ligne

	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/playlists/1/songs",
		testSongBody, bearerToken(t, 1))
	assertStatus(t, w, http.StatusConflict)
}

func TestAddSongToPlaylist_MissingFields(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/playlists/1/songs",
		`{"title":"Song"}`, bearerToken(t, 1)) // manque external_id et artist
	assertStatus(t, w, http.StatusBadRequest)
}

func TestAddSongToPlaylist_InvalidPlaylistID(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/playlists/notanid/songs",
		testSongBody, bearerToken(t, 1))
	assertStatus(t, w, http.StatusBadRequest)
}

// ── DELETE /users/:user_id/playlists/:playlist_id/songs/:entry_id ─────────────

func TestRemoveSongFromPlaylist_Success(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectExec("DELETE FROM playlist_songs").
		WillReturnResult(sqlmock.NewResult(0, 1))

	r := newRouter(db)
	w := do(t, r, http.MethodDelete, "/users/1/playlists/1/songs/1", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusNoContent)
}

func TestRemoveSongFromPlaylist_NotFound(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectExec("DELETE FROM playlist_songs").
		WillReturnResult(sqlmock.NewResult(0, 0)) // 0 lignes supprimées

	r := newRouter(db)
	w := do(t, r, http.MethodDelete, "/users/1/playlists/1/songs/999", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusNotFound)
}

func TestRemoveSongFromPlaylist_InvalidEntryID(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodDelete, "/users/1/playlists/1/songs/notanid", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusBadRequest)
}
