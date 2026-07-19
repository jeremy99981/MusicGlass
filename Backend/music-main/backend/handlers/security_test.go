package handlers

import (
	"net/http"
	"testing"
)

// routes protégées utilisées dans les deux tests de sécurité ci-dessous.
var protectedRoutes = []struct {
	method string
	path   string
	body   string
}{
	{http.MethodGet, "/users/1/profile", ""},
	{http.MethodPatch, "/users/1/profile", `{"first_name":"A"}`},
	{http.MethodGet, "/users/1/likes", ""},
	{http.MethodPost, "/users/1/likes", testSongBody},
	{http.MethodDelete, "/users/1/likes/1", ""},
	{http.MethodPatch, "/users/1/likes/1", `{"is_public":true}`},
	{http.MethodGet, "/users/1/playlists", ""},
	{http.MethodPost, "/users/1/playlists", `{"name":"test"}`},
	{http.MethodGet, "/users/1/playlists/1", ""},
	{http.MethodPatch, "/users/1/playlists/1", `{"name":"x"}`},
	{http.MethodDelete, "/users/1/playlists/1", ""},
	{http.MethodPost, "/users/1/playlists/1/songs", testSongBody},
	{http.MethodDelete, "/users/1/playlists/1/songs/1", ""},
}

// TestRequireAuth vérifie que toutes les routes protégées retournent 401
// lorsqu'aucun header Authorization n'est fourni.
func TestRequireAuth(t *testing.T) {
	db, _ := newDB(t)
	r := newRouter(db)

	for _, rt := range protectedRoutes {
		t.Run(rt.method+" "+rt.path, func(t *testing.T) {
			w := do(t, r, rt.method, rt.path, rt.body, "")
			assertStatus(t, w, http.StatusUnauthorized)
		})
	}
}

// TestPreventIDOR vérifie que toutes les routes protégées retournent 403
// quand le user_id du JWT ne correspond pas au :user_id de l'URL (attaque IDOR).
func TestPreventIDOR(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	tok := bearerToken(t, 1) // JWT pour user 1

	idorRoutes := []struct {
		method string
		path   string // /users/2/... → user différent du JWT
		body   string
	}{
		{http.MethodGet, "/users/2/profile", ""},
		{http.MethodPatch, "/users/2/profile", `{"first_name":"A"}`},
		{http.MethodGet, "/users/2/likes", ""},
		{http.MethodPost, "/users/2/likes", testSongBody},
		{http.MethodDelete, "/users/2/likes/1", ""},
		{http.MethodPatch, "/users/2/likes/1", `{"is_public":true}`},
		{http.MethodGet, "/users/2/playlists", ""},
		{http.MethodPost, "/users/2/playlists", `{"name":"test"}`},
		{http.MethodGet, "/users/2/playlists/1", ""},
		{http.MethodPatch, "/users/2/playlists/1", `{"name":"x"}`},
		{http.MethodDelete, "/users/2/playlists/1", ""},
		{http.MethodPost, "/users/2/playlists/1/songs", testSongBody},
		{http.MethodDelete, "/users/2/playlists/1/songs/1", ""},
	}

	for _, rt := range idorRoutes {
		t.Run(rt.method+" "+rt.path, func(t *testing.T) {
			w := do(t, r, rt.method, rt.path, rt.body, tok)
			assertStatus(t, w, http.StatusForbidden)
		})
	}
}

// TestInvalidJWT vérifie qu'un token JWT malformé retourne 401.
func TestInvalidJWT(t *testing.T) {
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodGet, "/users/1/profile", "", "Bearer invalid.token.here")
	assertStatus(t, w, http.StatusUnauthorized)
}

// TestWrongJWTSecret vérifie qu'un token signé avec un mauvais secret retourne 401.
func TestWrongJWTSecret(t *testing.T) {
	t.Setenv("JWT_SECRET", "first-secret-xxxxxxxxxxxxxxxxxxxxxxx")
	tok := bearerToken(t, 1)

	t.Setenv("JWT_SECRET", "second-secret-xxxxxxxxxxxxxxxxxxxxx")
	db, _ := newDB(t)
	r := newRouter(db)

	w := do(t, r, http.MethodGet, "/users/1/profile", "", tok)
	assertStatus(t, w, http.StatusUnauthorized)
}

// TestMalformedAuthHeader vérifie qu'un header Authorization sans préfixe Bearer retourne 401.
func TestMalformedAuthHeader(t *testing.T) {
	db, _ := newDB(t)
	r := newRouter(db)
	w := do(t, r, http.MethodGet, "/users/1/profile", "", "Token sometoken")
	assertStatus(t, w, http.StatusUnauthorized)
}

// TestIDORNonNumericUserID vérifie qu'un user_id non numérique retourne 400.
func TestIDORNonNumericUserID(t *testing.T) {
	t.Setenv("JWT_SECRET", testJWTSecret)
	db, _ := newDB(t)
	r := newRouter(db)
	tok := bearerToken(t, 1)
	w := do(t, r, http.MethodGet, "/users/abc/profile", "", tok)
	// SelfOnly ne peut pas comparer "abc" à l'int du JWT → 400 ou 403
	if w.Code != http.StatusBadRequest && w.Code != http.StatusForbidden {
		t.Errorf("expected 400 or 403, got %d", w.Code)
	}
}
