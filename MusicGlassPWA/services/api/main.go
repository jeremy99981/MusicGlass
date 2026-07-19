package main

import (
	"log"
	"os"
	"strings"
	"time"

	"app/db"
	_ "app/docs"
	"app/handlers"
	"app/middleware"
	appws "app/ws"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	swaggerFiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"
)

// @title Music API
// @version 1.0
// @description API backend pour gestion des utilisateurs, likes, playlists et écoute partagée en temps réel
// @BasePath /
// @securityDefinitions.apikey BearerAuth
// @in header
// @name Authorization

func main() {
	database, err := db.Connect()
	if err != nil {
		log.Fatalf("database connection failed: %v", err)
	}
	defer database.Close()

	if err := db.Migrate(database); err != nil {
		log.Fatalf("database migration failed: %v", err)
	}

	hub := appws.NewHub()

	r := gin.Default()
	r.Use(middleware.SecurityHeaders())

	allowedOrigins := os.Getenv("CORS_ALLOWED_ORIGINS")
	if allowedOrigins == "" {
		allowedOrigins = "http://localhost:3000"
	}
	r.Use(cors.New(cors.Config{
		AllowOrigins:     strings.Split(allowedOrigins, ","),
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization", "X-CSRF-Token"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}))

	h := handlers.New(database, hub)

	r.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))
	r.GET("/health", h.Health)
	r.GET("/api/v2/health", h.Health)

	// ── Auth ─────────────────────────────────────────────────────────────────
	auth := r.Group("/auth")
	{
		auth.POST("/signup", h.Signup)
		auth.POST("/login", h.Login)
		auth.POST("/refresh", h.Refresh)
	}

	// ── Utilisateurs (AuthRequired + SelfOnly sur chaque sous-route) ─────────
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

		// ── Amis ─────────────────────────────────────────────────────────────
		self.GET("/friends", h.ListFriends)
		self.GET("/friends/requests", h.ListFriendRequests)
		self.POST("/friends/requests", h.SendFriendRequest)
		self.POST("/friends/requests/:request_id/accept", h.AcceptFriendRequest)
		self.DELETE("/friends/requests/:request_id", h.DeclineFriendRequest)
		self.DELETE("/friends/:friend_id", h.RemoveFriend)
	}

	// ── Sessions d'écoute (auth requise, pas de SelfOnly) ────────────────────
	sessions := r.Group("/sessions", middleware.AuthRequired())
	{
		sessions.POST("", h.CreateSession)
		sessions.GET("/:code", h.GetSession)
		sessions.DELETE("/:code", h.EndSession)
	}

	// ── WebSocket (auth via query param ?token=<JWT>) ─────────────────────────
	r.GET("/ws/:code", h.ServeWS)

	// Web API v2 uses same-origin HttpOnly cookies while all v1 routes remain
	// unchanged for the Flutter clients during migration.
	v2 := r.Group("/api/v2")
	{
		webAuth := v2.Group("/auth")
		webAuth.POST("/signup", h.WebSignup)
		webAuth.POST("/login", h.WebLogin)
		webAuth.POST("/refresh", h.WebRefresh)
		webAuth.POST("/logout", middleware.CSRFRequired(), h.WebLogout)
		v2.GET("/catalog/status", h.WebCatalogStatus)
		v2.GET("/catalog/home", h.WebCatalogHome)
		v2.GET("/catalog/playlist/:id", h.WebCatalogPlaylist)
		v2.GET("/catalog/radio", h.WebCatalogRadio)
		v2.GET("/catalog/search", h.WebCatalogSearch)
		v2.GET("/media/resolve/:track_id", h.WebMediaResolve)
		v2.GET("/media/stream/:track_id", h.WebMediaStream) // Moved out of protected to allow audio tag to fetch
		v2.GET("/media/artwork", h.WebMediaArtwork)

		protected := v2.Group("", middleware.WebAuthRequired(), middleware.CSRFRequired())
		protected.GET("/me", h.WebMe)
		protected.POST("/auth/revoke-all", h.WebRevokeAll)
		protected.POST("/sessions", h.CreateSession)
		protected.GET("/sessions/:code", h.GetSession)
		protected.DELETE("/sessions/:code", h.EndSession)
		protected.GET("/library", h.WebLibrary)
		protected.GET("/library/likes", h.WebLibraryLikes)
		protected.POST("/library/likes", h.WebLibraryAddLike)
		protected.DELETE("/library/likes/:like_id", h.WebLibraryRemoveLike)
		protected.GET("/library/playlists", h.WebLibraryPlaylists)
		protected.POST("/library/playlists", h.WebLibraryCreatePlaylist)
		protected.POST("/library/playlists/:playlist_id/songs", h.WebLibraryAddSongToPlaylist)
		protected.GET("/search/history", h.WebSearchHistory)
		protected.POST("/search/history", h.WebRecordSearch)
		protected.DELETE("/search/history", h.WebClearSearchHistory)
		protected.POST("/providers/youtube/connect", h.WebYouTubeProviderConnect)
	}
	v2.GET("/providers/youtube", h.WebYouTubeProviderStatus)
	v2.GET("/providers/youtube/oauth/callback", h.WebYouTubeOAuthCallback)
	v2.GET("/sessions/:code/ws", h.ServeWS)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8081"
	}

	log.Printf("server listening on :%s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("server error: %v", err)
	}
}
