package handlers

import (
	"net/http"
	"testing"
	"time"

	"github.com/lib/pq"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
)

// ── GET /users/:user_id/likes ─────────────────────────────────────────────────

func TestListLikes_Empty(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("FROM user_likes ul").
		WillReturnRows(mock.NewRows([]string{
			"id", "is_public", "created_at",
			"song_id", "external_id", "title", "artist", "album", "cover_url", "duration_ms",
		}))

	r := newRouter(db)
	w := do(t, r, http.MethodGet, "/users/1/likes", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusOK)
}

func TestListLikes_WithData(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("FROM user_likes ul").
		WillReturnRows(mock.NewRows([]string{
			"id", "is_public", "created_at",
			"song_id", "external_id", "title", "artist", "album", "cover_url", "duration_ms",
		}).
			AddRow(1, false, time.Now(), 10, "sp:abc", "Song", "Artist", "", "", 0).
			AddRow(2, true, time.Now(), 11, "sp:def", "Song2", "Artist2", "", "", 213000))

	r := newRouter(db)
	w := do(t, r, http.MethodGet, "/users/1/likes", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusOK)
}

// ── POST /users/:user_id/likes ────────────────────────────────────────────────

func TestAddLike_Success(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("INSERT INTO songs").WillReturnRows(songRow(mock))
	mock.ExpectQuery("INSERT INTO user_likes").WillReturnRows(likeRow(mock))

	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/likes", testSongBody, bearerToken(t, 1))
	assertStatus(t, w, http.StatusCreated)
}

func TestAddLike_MissingExternalID(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/likes",
		`{"title":"Song","artist":"Artist"}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusBadRequest)
}

func TestAddLike_MissingTitle(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/likes",
		`{"external_id":"sp:abc","artist":"Artist"}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusBadRequest)
}

func TestAddLike_EmptyBody(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/likes", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusBadRequest)
}

func TestAddLike_AlreadyLiked(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("INSERT INTO songs").WillReturnRows(songRow(mock))
	mock.ExpectQuery("INSERT INTO user_likes").
		WillReturnError(&pq.Error{Code: "23505"})

	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/likes", testSongBody, bearerToken(t, 1))
	assertStatus(t, w, http.StatusConflict)
}

// ── DELETE /users/:user_id/likes/:like_id ─────────────────────────────────────

func TestRemoveLike_Success(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectExec("DELETE FROM user_likes WHERE id").
		WillReturnResult(sqlmock.NewResult(0, 1))

	r := newRouter(db)
	w := do(t, r, http.MethodDelete, "/users/1/likes/5", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusNoContent)
}

func TestRemoveLike_NotFound(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectExec("DELETE FROM user_likes WHERE id").
		WillReturnResult(sqlmock.NewResult(0, 0)) // 0 lignes supprimées

	r := newRouter(db)
	w := do(t, r, http.MethodDelete, "/users/1/likes/999", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusNotFound)
}

func TestRemoveLike_InvalidID(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodDelete, "/users/1/likes/notanid", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusBadRequest)
}

// ── PATCH /users/:user_id/likes/:like_id ──────────────────────────────────────

func TestSetLikeVisibility_Public(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("UPDATE user_likes SET is_public").
		WillReturnRows(mock.NewRows([]string{
			"id", "is_public", "created_at",
			"song_id", "external_id", "title", "artist", "album", "cover_url", "duration_ms",
		}).AddRow(5, true, time.Now(), 10, "sp:abc123", "Never Gonna Give You Up", "Rick Astley", "", "", 0))

	r := newRouter(db)
	w := do(t, r, http.MethodPatch, "/users/1/likes/5",
		`{"is_public":true}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusOK)
}

func TestSetLikeVisibility_Private(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("UPDATE user_likes SET is_public").
		WillReturnRows(mock.NewRows([]string{
			"id", "is_public", "created_at",
			"song_id", "external_id", "title", "artist", "album", "cover_url", "duration_ms",
		}).AddRow(5, false, time.Now(), 10, "sp:abc123", "Never Gonna Give You Up", "Rick Astley", "", "", 0))

	r := newRouter(db)
	w := do(t, r, http.MethodPatch, "/users/1/likes/5",
		`{"is_public":false}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusOK)
}

func TestSetLikeVisibility_NotFound(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("UPDATE user_likes SET is_public").
		WillReturnRows(mock.NewRows([]string{
			"id", "is_public", "created_at",
			"song_id", "external_id", "title", "artist", "album", "cover_url", "duration_ms",
		})) // aucune ligne → ErrLikeNotFound

	r := newRouter(db)
	w := do(t, r, http.MethodPatch, "/users/1/likes/999",
		`{"is_public":true}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusNotFound)
}

func TestSetLikeVisibility_MissingField(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	// is_public est required → 400 si absent
	w := do(t, r, http.MethodPatch, "/users/1/likes/5",
		`{}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusBadRequest)
}
