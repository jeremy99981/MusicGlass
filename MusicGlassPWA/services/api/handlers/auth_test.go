package handlers

import (
	"net/http"
	"testing"
	"time"

	"github.com/lib/pq"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
)

// ── Signup ────────────────────────────────────────────────────────────────────

func TestSignup_Success(t *testing.T) {
	db, mock := newDB(t)
	mock.ExpectQuery("INSERT INTO users").
		WillReturnRows(mock.NewRows([]string{"id", "name", "email"}).
			AddRow(1, "John Doe", "john@example.com"))

	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/auth/signup",
		`{"name":"John Doe","email":"john@example.com","password":"password123"}`, "")
	assertStatus(t, w, http.StatusCreated)
}

func TestSignup_MissingPassword(t *testing.T) {
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/auth/signup",
		`{"name":"John","email":"john@example.com"}`, "")
	assertStatus(t, w, http.StatusBadRequest)
}

func TestSignup_InvalidEmail(t *testing.T) {
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/auth/signup",
		`{"name":"John","email":"not-an-email","password":"password123"}`, "")
	assertStatus(t, w, http.StatusBadRequest)
}

func TestSignup_PasswordTooShort(t *testing.T) {
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/auth/signup",
		`{"name":"John","email":"john@example.com","password":"short"}`, "")
	assertStatus(t, w, http.StatusBadRequest)
}

func TestSignup_EmailConflict(t *testing.T) {
	db, mock := newDB(t)
	mock.ExpectQuery("INSERT INTO users").
		WillReturnError(&pq.Error{Code: "23505"})

	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/auth/signup",
		`{"name":"John","email":"existing@example.com","password":"password123"}`, "")
	assertStatus(t, w, http.StatusConflict)
}

func TestSignup_EmptyBody(t *testing.T) {
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/auth/signup", "", "")
	assertStatus(t, w, http.StatusBadRequest)
}

// ── Login ─────────────────────────────────────────────────────────────────────

func TestLogin_Success(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)

	mock.ExpectQuery("SELECT id, password_hash FROM users").
		WillReturnRows(mock.NewRows([]string{"id", "password_hash"}).
			AddRow(1, testPasswordHash))
	mock.ExpectExec("INSERT INTO refresh_tokens").
		WillReturnResult(sqlmock.NewResult(1, 1))

	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/auth/login",
		`{"email":"john@example.com","password":"password123"}`, "")
	assertStatus(t, w, http.StatusOK)
}

func TestLogin_InvalidCredentials(t *testing.T) {
	db, mock := newDB(t)
	mock.ExpectQuery("SELECT id, password_hash FROM users").
		WillReturnRows(mock.NewRows([]string{"id", "password_hash"}).
			AddRow(1, testPasswordHash))

	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/auth/login",
		`{"email":"john@example.com","password":"wrongpassword"}`, "")
	assertStatus(t, w, http.StatusUnauthorized)
}

func TestLogin_UserNotFound(t *testing.T) {
	db, mock := newDB(t)
	mock.ExpectQuery("SELECT id, password_hash FROM users").
		WillReturnRows(mock.NewRows([]string{"id", "password_hash"})) // aucune ligne

	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/auth/login",
		`{"email":"unknown@example.com","password":"password123"}`, "")
	assertStatus(t, w, http.StatusUnauthorized)
}

func TestLogin_MissingEmail(t *testing.T) {
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/auth/login",
		`{"password":"password123"}`, "")
	assertStatus(t, w, http.StatusBadRequest)
}

func TestLogin_EmptyBody(t *testing.T) {
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/auth/login", "", "")
	assertStatus(t, w, http.StatusBadRequest)
}

// ── Refresh ───────────────────────────────────────────────────────────────────

func TestRefresh_Success(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	plaintext, hash := fakeRefreshToken()

	db, mock := newDB(t)
	mock.ExpectQuery("SELECT id, user_id, expires_at, revoked FROM refresh_tokens").
		WillReturnRows(mock.NewRows([]string{"id", "user_id", "expires_at", "revoked"}).
			AddRow(1, 1, time.Now().Add(24*time.Hour), false))
	mock.ExpectBegin()
	mock.ExpectExec("UPDATE refresh_tokens SET revoked").
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec("INSERT INTO refresh_tokens").
		WillReturnResult(sqlmock.NewResult(2, 1))
	mock.ExpectCommit()

	r := newRouter(db)
	body := `{"refresh_token":"` + plaintext + `"}`
	w := do(t, r, http.MethodPost, "/auth/refresh", body, "")
	assertStatus(t, w, http.StatusOK)

	_ = hash // le service hache le token avant de l'envoyer en DB
}

func TestRefresh_InvalidToken(t *testing.T) {
	db, mock := newDB(t)
	mock.ExpectQuery("SELECT id, user_id, expires_at, revoked FROM refresh_tokens").
		WillReturnRows(mock.NewRows([]string{"id", "user_id", "expires_at", "revoked"}))

	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/auth/refresh",
		`{"refresh_token":"totally-invalid-token"}`, "")
	assertStatus(t, w, http.StatusUnauthorized)
}

func TestRefresh_RevokedToken(t *testing.T) {
	plaintext, _ := fakeRefreshToken()

	db, mock := newDB(t)
	mock.ExpectQuery("SELECT id, user_id, expires_at, revoked FROM refresh_tokens").
		WillReturnRows(mock.NewRows([]string{"id", "user_id", "expires_at", "revoked"}).
			AddRow(1, 1, time.Now().Add(24*time.Hour), true)) // revoked = true

	r := newRouter(db)
	body := `{"refresh_token":"` + plaintext + `"}`
	w := do(t, r, http.MethodPost, "/auth/refresh", body, "")
	assertStatus(t, w, http.StatusUnauthorized)
}

func TestRefresh_ExpiredToken(t *testing.T) {
	plaintext, _ := fakeRefreshToken()

	db, mock := newDB(t)
	mock.ExpectQuery("SELECT id, user_id, expires_at, revoked FROM refresh_tokens").
		WillReturnRows(mock.NewRows([]string{"id", "user_id", "expires_at", "revoked"}).
			AddRow(1, 1, time.Now().Add(-1*time.Hour), false)) // expiré

	r := newRouter(db)
	body := `{"refresh_token":"` + plaintext + `"}`
	w := do(t, r, http.MethodPost, "/auth/refresh", body, "")
	assertStatus(t, w, http.StatusUnauthorized)
}

func TestRefresh_MissingBody(t *testing.T) {
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/auth/refresh", "", "")
	assertStatus(t, w, http.StatusBadRequest)
}
