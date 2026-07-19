package handlers

import (
	"database/sql"
	"net/http"
	"testing"

	"github.com/lib/pq"
)

// ── GET /users/:user_id/profile ───────────────────────────────────────────────

func TestGetProfile_Success(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("SELECT id, name, email, first_name, last_name FROM users").
		WillReturnRows(userRow(mock))

	r := newRouter(db)
	w := do(t, r, http.MethodGet, "/users/1/profile", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusOK)
}

func TestGetProfile_NotFound(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("SELECT id, name, email, first_name, last_name FROM users").
		WillReturnRows(mock.NewRows([]string{"id", "name", "email", "first_name", "last_name"}))

	r := newRouter(db)
	w := do(t, r, http.MethodGet, "/users/1/profile", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusNotFound)
}

// ── PATCH /users/:user_id/profile ─────────────────────────────────────────────

func TestUpdateProfile_Success(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("UPDATE users SET").
		WillReturnRows(mock.NewRows([]string{"id", "name", "email", "first_name", "last_name"}).
			AddRow(1, "John Doe", "john@example.com", sql.NullString{String: "John", Valid: true}, sql.NullString{}))

	r := newRouter(db)
	w := do(t, r, http.MethodPatch, "/users/1/profile",
		`{"first_name":"John"}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusOK)
}

func TestUpdateProfile_EmailAndName(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("UPDATE users SET").
		WillReturnRows(mock.NewRows([]string{"id", "name", "email", "first_name", "last_name"}).
			AddRow(1, "John Doe", "new@example.com",
				sql.NullString{String: "John", Valid: true},
				sql.NullString{String: "Doe", Valid: true}))

	r := newRouter(db)
	w := do(t, r, http.MethodPatch, "/users/1/profile",
		`{"first_name":"John","last_name":"Doe","email":"new@example.com"}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusOK)
}

func TestUpdateProfile_NoFields(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPatch, "/users/1/profile",
		`{}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusBadRequest)
}

func TestUpdateProfile_EmailConflict(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("UPDATE users SET").
		WillReturnError(&pq.Error{Code: "23505"})

	r := newRouter(db)
	w := do(t, r, http.MethodPatch, "/users/1/profile",
		`{"email":"taken@example.com"}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusConflict)
}

func TestUpdateProfile_InvalidEmail(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPatch, "/users/1/profile",
		`{"email":"not-a-valid-email"}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusBadRequest)
}

func TestUpdateProfile_EmptyFirstName(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	// min=1 → chaîne vide invalide
	w := do(t, r, http.MethodPatch, "/users/1/profile",
		`{"first_name":""}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusBadRequest)
}
