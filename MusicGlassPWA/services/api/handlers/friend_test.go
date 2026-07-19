package handlers

import (
	"net/http"
	"testing"
	"time"

	"github.com/lib/pq"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
)

var friendshipCols = []string{"id", "requester_id", "addressee_id", "status", "created_at"}
var friendCols = []string{"id", "name", "email"}

func friendshipRow(mock sqlmock.Sqlmock, status string) *sqlmock.Rows {
	return mock.NewRows(friendshipCols).
		AddRow(1, 1, 2, status, time.Now())
}

// ── GET /users/:user_id/friends ───────────────────────────────────────────────

func TestListFriends_Empty(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("FROM friendships f").
		WillReturnRows(mock.NewRows(friendCols))

	r := newRouter(db)
	w := do(t, r, http.MethodGet, "/users/1/friends", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusOK)
}

func TestListFriends_WithData(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("FROM friendships f").
		WillReturnRows(mock.NewRows(friendCols).
			AddRow(2, "Bob", "bob@example.com").
			AddRow(3, "Charlie", "charlie@example.com"))

	r := newRouter(db)
	w := do(t, r, http.MethodGet, "/users/1/friends", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusOK)
}

// ── GET /users/:user_id/friends/requests ──────────────────────────────────────

func TestListFriendRequests_Empty(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("FROM friendships").
		WillReturnRows(mock.NewRows(friendshipCols))

	r := newRouter(db)
	w := do(t, r, http.MethodGet, "/users/1/friends/requests", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusOK)
}

func TestListFriendRequests_WithPending(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("FROM friendships").
		WillReturnRows(friendshipRow(mock, "pending"))

	r := newRouter(db)
	w := do(t, r, http.MethodGet, "/users/1/friends/requests", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusOK)
}

// ── POST /users/:user_id/friends/requests ─────────────────────────────────────

func TestSendFriendRequest_Success(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("INSERT INTO friendships").
		WillReturnRows(friendshipRow(mock, "pending"))

	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/friends/requests",
		`{"addressee_id":2}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusCreated)
}

func TestSendFriendRequest_ToSelf(t *testing.T) {
	// addressee_id = 1 = user_id du JWT → ErrCannotFriendYourself
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/friends/requests",
		`{"addressee_id":1}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusBadRequest)
}

func TestSendFriendRequest_AlreadyExists(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("INSERT INTO friendships").
		WillReturnError(&pq.Error{Code: "23505"})

	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/friends/requests",
		`{"addressee_id":2}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusConflict)
}

func TestSendFriendRequest_MissingBody(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/friends/requests", "", bearerToken(t, 1))
	assertStatus(t, w, http.StatusBadRequest)
}

func TestSendFriendRequest_MissingAddresseeID(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/friends/requests",
		`{}`, bearerToken(t, 1))
	assertStatus(t, w, http.StatusBadRequest)
}

// ── POST /users/:user_id/friends/requests/:request_id/accept ─────────────────

func TestAcceptFriendRequest_Success(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("UPDATE friendships SET status").
		WillReturnRows(friendshipRow(mock, "accepted"))

	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/friends/requests/5/accept",
		"", bearerToken(t, 1))
	assertStatus(t, w, http.StatusOK)
}

func TestAcceptFriendRequest_NotFound(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectQuery("UPDATE friendships SET status").
		WillReturnRows(mock.NewRows(friendshipCols))

	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/friends/requests/999/accept",
		"", bearerToken(t, 1))
	assertStatus(t, w, http.StatusNotFound)
}

func TestAcceptFriendRequest_InvalidID(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodPost, "/users/1/friends/requests/notanid/accept",
		"", bearerToken(t, 1))
	assertStatus(t, w, http.StatusBadRequest)
}

// ── DELETE /users/:user_id/friends/requests/:request_id ──────────────────────

func TestDeclineFriendRequest_Success(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectExec("DELETE FROM friendships").
		WillReturnResult(sqlmock.NewResult(0, 1))

	r := newRouter(db)
	w := do(t, r, http.MethodDelete, "/users/1/friends/requests/5",
		"", bearerToken(t, 1))
	assertStatus(t, w, http.StatusNoContent)
}

func TestDeclineFriendRequest_NotFound(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectExec("DELETE FROM friendships").
		WillReturnResult(sqlmock.NewResult(0, 0))

	r := newRouter(db)
	w := do(t, r, http.MethodDelete, "/users/1/friends/requests/999",
		"", bearerToken(t, 1))
	assertStatus(t, w, http.StatusNotFound)
}

// ── DELETE /users/:user_id/friends/:friend_id ─────────────────────────────────

func TestRemoveFriend_Success(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectExec("DELETE FROM friendships").
		WillReturnResult(sqlmock.NewResult(0, 1))

	r := newRouter(db)
	w := do(t, r, http.MethodDelete, "/users/1/friends/2",
		"", bearerToken(t, 1))
	assertStatus(t, w, http.StatusNoContent)
}

func TestRemoveFriend_NotFound(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, mock := newDB(t)
	mock.ExpectExec("DELETE FROM friendships").
		WillReturnResult(sqlmock.NewResult(0, 0))

	r := newRouter(db)
	w := do(t, r, http.MethodDelete, "/users/1/friends/999",
		"", bearerToken(t, 1))
	assertStatus(t, w, http.StatusNotFound)
}

func TestRemoveFriend_InvalidID(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodDelete, "/users/1/friends/notanid",
		"", bearerToken(t, 1))
	assertStatus(t, w, http.StatusBadRequest)
}

// ── Sécurité : amis ───────────────────────────────────────────────────────────

func TestFriendRoutes_RequireAuth(t *testing.T) {
	routes := []struct{ method, path, body string }{
		{http.MethodGet, "/users/1/friends", ""},
		{http.MethodGet, "/users/1/friends/requests", ""},
		{http.MethodPost, "/users/1/friends/requests", `{"addressee_id":2}`},
		{http.MethodPost, "/users/1/friends/requests/1/accept", ""},
		{http.MethodDelete, "/users/1/friends/requests/1", ""},
		{http.MethodDelete, "/users/1/friends/2", ""},
	}
	db, _ := newDB(t)
	r := newRouter(db)
	for _, rt := range routes {
		t.Run(rt.method+" "+rt.path, func(t *testing.T) {
			w := do(t, r, rt.method, rt.path, rt.body, "")
			assertStatus(t, w, http.StatusUnauthorized)
		})
	}
}

func TestFriendRoutes_PreventIDOR(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	routes := []struct{ method, path, body string }{
		{http.MethodGet, "/users/2/friends", ""},
		{http.MethodGet, "/users/2/friends/requests", ""},
		{http.MethodPost, "/users/2/friends/requests", `{"addressee_id":3}`},
		{http.MethodPost, "/users/2/friends/requests/1/accept", ""},
		{http.MethodDelete, "/users/2/friends/requests/1", ""},
		{http.MethodDelete, "/users/2/friends/3", ""},
	}
	db, _ := newDB(t)
	r := newRouter(db)
	tok := bearerToken(t, 1) // token user 1, routes user 2
	for _, rt := range routes {
		t.Run(rt.method+" "+rt.path, func(t *testing.T) {
			w := do(t, r, rt.method, rt.path, rt.body, tok)
			assertStatus(t, w, http.StatusForbidden)
		})
	}
}
