package handlers

import (
	"net/http"
	"testing"
	"time"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
)

var sessionCols = []string{"id", "host_id", "code", "is_active", "created_at"}

func sessionRow(mock sqlmock.Sqlmock) *sqlmock.Rows {
	return mock.NewRows(sessionCols).
		AddRow(1, 1, "ABCD1234", true, time.Now())
}

// ── POST /sessions ────────────────────────────────────────────────────────────

func TestCreateSession_Success(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("INSERT INTO listen_sessions").
		WillReturnRows(sessionRow(mock))

	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/sessions", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusCreated)
}

func TestCreateSession_RequiresAuth(t *testing.T) {
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/sessions", "", "")
	assertStatus(t, w, http.StatusUnauthorized)
}

// ── GET /sessions/:code ───────────────────────────────────────────────────────

func TestGetSession_Success(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("SELECT id, host_id, code, is_active, created_at FROM listen_sessions").
		WillReturnRows(sessionRow(mock))

	r := newRouter(db)
	w := do(t, r, http.MethodGet, "/sessions/ABCD1234", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusOK)
}

func TestGetSession_NotFound(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("SELECT id, host_id, code, is_active, created_at FROM listen_sessions").
		WillReturnRows(mock.NewRows(sessionCols))

	r := newRouter(db)
	w := do(t, r, http.MethodGet, "/sessions/ZZZZZZZZ", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusNotFound)
}

func TestGetSession_RequiresAuth(t *testing.T) {
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodGet, "/sessions/ABCD1234", "", "")
	assertStatus(t, w, http.StatusUnauthorized)
}

// ── DELETE /sessions/:code ────────────────────────────────────────────────────

func TestEndSession_Success(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectExec("UPDATE listen_sessions SET is_active").
		WillReturnResult(sqlmock.NewResult(0, 1))

	r := newRouter(db)
	w := do(t, r, http.MethodDelete, "/sessions/ABCD1234", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusNoContent)
}

func TestEndSession_NotFound(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectExec("UPDATE listen_sessions SET is_active").
		WillReturnResult(sqlmock.NewResult(0, 0))

	r := newRouter(db)
	w := do(t, r, http.MethodDelete, "/sessions/ZZZZZZZZ", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusNotFound)
}

func TestEndSession_RequiresAuth(t *testing.T) {
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodDelete, "/sessions/ABCD1234", "", "")
	assertStatus(t, w, http.StatusUnauthorized)
}

// ── WebSocket : validation avant l'upgrade ────────────────────────────────────

func TestServeWS_MissingToken(t *testing.T) {
	db, _ := newDB(t)
	r := newRouter(db)
	// Sans ?token= → 401 avant même l'upgrade WebSocket
	w := do(t, r, http.MethodGet, "/ws/ABCD1234", "", "")
	assertStatus(t, w, http.StatusUnauthorized)
}

func TestServeWS_InvalidToken(t *testing.T) {
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodGet, "/ws/ABCD1234?token=bad.token.value", "", "")
	assertStatus(t, w, http.StatusUnauthorized)
}

func TestServeWS_SessionNotFound(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	// Session introuvable en DB
	mock.ExpectQuery("SELECT id, host_id, code, is_active, created_at FROM listen_sessions").
		WillReturnRows(mock.NewRows(sessionCols))

	r := newRouter(db)
	tok := bearerToken(t, 1)
	// Requête HTTP standard (pas WebSocket) — le handler répond 404 avant l'upgrade.
	w := do(t, r, http.MethodGet, "/ws/ZZZZZZZZ?token="+tok[7:], "", "")
	assertStatus(t, w, http.StatusNotFound)
}
