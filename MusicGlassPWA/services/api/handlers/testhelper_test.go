package handlers

import (
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"io"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"app/middleware"
	"app/services"
	appws "app/ws"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

const (
	testJWTSecret = "test-secret-exactly-32-chars-xxxx"
	testPassword  = "password123"
	testSongBody  = `{"external_id":"sp:abc123","title":"Never Gonna Give You Up","artist":"Rick Astley"}`
)

var testPasswordHash string

func init() {
	h, err := bcrypt.GenerateFromPassword([]byte(testPassword), bcrypt.MinCost)
	if err != nil {
		panic("testhelper: cannot hash test password: " + err.Error())
	}
	testPasswordHash = string(h)
}

// newDB crée un sqlmock frais pour un seul test.
func newDB(t *testing.T) (*sql.DB, sqlmock.Sqlmock) {
	t.Helper()
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New: %v", err)
	}
	t.Cleanup(func() { db.Close() })
	return db, mock
}

// newRouter construit le routeur Gin complet avec middleware et routes, identique à main.go.
func newRouter(db *sql.DB) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(middleware.SecurityHeaders())

	h := New(db, appws.NewHub())
	r.GET("/health", h.Health)

	auth := r.Group("/auth")
	{
		auth.POST("/signup", h.Signup)
		auth.POST("/login", h.Login)
		auth.POST("/refresh", h.Refresh)
	}

	users := r.Group("/users", middleware.AuthRequired())
	self := users.Group("/:user_id", middleware.SelfOnly())
	{
		self.GET("/profile", h.GetProfile)
		self.PATCH("/profile", h.UpdateProfile)

		self.GET("/likes", h.ListLikes)
		self.POST("/likes", h.AddLike)
		self.DELETE("/likes/:like_id", h.RemoveLike)
		self.PATCH("/likes/:like_id", h.SetLikeVisibility)

		self.GET("/playlists", h.ListPlaylists)
		self.POST("/playlists", h.CreatePlaylist)
		self.GET("/playlists/:playlist_id", h.GetPlaylist)
		self.PATCH("/playlists/:playlist_id", h.UpdatePlaylist)
		self.DELETE("/playlists/:playlist_id", h.DeletePlaylist)
		self.POST("/playlists/:playlist_id/songs", h.AddSongToPlaylist)
		self.DELETE("/playlists/:playlist_id/songs/:entry_id", h.RemoveSongFromPlaylist)

		self.GET("/friends", h.ListFriends)
		self.GET("/friends/requests", h.ListFriendRequests)
		self.POST("/friends/requests", h.SendFriendRequest)
		self.POST("/friends/requests/:request_id/accept", h.AcceptFriendRequest)
		self.DELETE("/friends/requests/:request_id", h.DeclineFriendRequest)
		self.DELETE("/friends/:friend_id", h.RemoveFriend)
	}

	sessions := r.Group("/sessions", middleware.AuthRequired())
	{
		sessions.POST("", h.CreateSession)
		sessions.GET("/:code", h.GetSession)
		sessions.DELETE("/:code", h.EndSession)
	}

	r.GET("/ws/:code", h.ServeWS)

	return r
}

// bearerToken génère un JWT valide pour userID et configure JWT_SECRET dans l'env du test.
func bearerToken(t *testing.T, userID int) string {
	t.Helper()
	t.Setenv("JWT_SECRET", testJWTSecret)
	tok, err := services.GenerateAccessToken(userID)
	if err != nil {
		t.Fatalf("GenerateAccessToken: %v", err)
	}
	return "Bearer " + tok
}

// do envoie une requête HTTP au routeur et retourne la réponse enregistrée.
func do(t *testing.T, r *gin.Engine, method, path, body, auth string) *httptest.ResponseRecorder {
	t.Helper()
	var reader io.Reader
	if body != "" {
		reader = strings.NewReader(body)
	}
	req := httptest.NewRequest(method, path, reader)
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	if auth != "" {
		req.Header.Set("Authorization", auth)
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

// assertStatus échoue le test si le code HTTP ne correspond pas.
func assertStatus(t *testing.T, w *httptest.ResponseRecorder, want int) {
	t.Helper()
	if w.Code != want {
		t.Errorf("HTTP %d, want %d — body: %s", w.Code, want, w.Body)
	}
}

// fakeRefreshToken retourne un token de refresh déterministe et son hash SHA-256
// (le format stocké en base par le service).
func fakeRefreshToken() (plaintext, hash string) {
	b := make([]byte, 32)
	for i := range b {
		b[i] = byte(i + 1)
	}
	plaintext = base64.RawURLEncoding.EncodeToString(b)
	sum := sha256.Sum256([]byte(plaintext))
	hash = hex.EncodeToString(sum[:])
	return
}

// userRow retourne une ligne sqlmock représentant un utilisateur (colonnes GetByID).
func userRow(mock sqlmock.Sqlmock) *sqlmock.Rows {
	return mock.NewRows([]string{"id", "name", "email", "first_name", "last_name"}).
		AddRow(1, "John Doe", "john@example.com", sql.NullString{}, sql.NullString{})
}

// songRow retourne une ligne sqlmock représentant une chanson (colonnes upsertSong).
func songRow(mock sqlmock.Sqlmock) *sqlmock.Rows {
	return mock.NewRows([]string{"id", "external_id", "title", "artist", "album", "cover_url", "duration_ms"}).
		AddRow(10, "sp:abc123", "Never Gonna Give You Up", "Rick Astley", "", "", 0)
}

// likeRow retourne une ligne sqlmock représentant la partie like (colonnes INSERT user_likes RETURNING).
func likeRow(mock sqlmock.Sqlmock) *sqlmock.Rows {
	return mock.NewRows([]string{"id", "is_public", "created_at"}).
		AddRow(5, false, time.Now())
}

// playlistSummaryRow retourne une ligne pour ListByUser.
func playlistSummaryRow(mock sqlmock.Sqlmock) *sqlmock.Rows {
	return mock.NewRows([]string{"id", "name", "description", "is_public", "created_at", "updated_at", "song_count"}).
		AddRow(1, "Ma playlist", "", false, time.Now(), time.Now(), 0)
}

// playlistRow retourne une ligne pour GetByID / CreatePlaylist / UpdatePlaylist.
func playlistRow(mock sqlmock.Sqlmock) *sqlmock.Rows {
	return mock.NewRows([]string{"id", "name", "description", "is_public", "created_at", "updated_at"}).
		AddRow(1, "Ma playlist", "", false, time.Now(), time.Now())
}
