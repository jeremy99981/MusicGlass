package handlers

import (
	"database/sql"
	"net/http"
	"strconv"

	"app/services"
	appws "app/ws"

	"github.com/gin-gonic/gin"
)

// Handler regroupe la connexion DB, les services pré-initialisés et le hub WebSocket.
type Handler struct {
	db        *sql.DB
	users     *services.UserService
	auth      *services.AuthService
	likes     *services.LikeService
	playlists *services.PlaylistService
	friends   *services.FriendService
	sessions  *services.SessionService
	hub       *appws.Hub
}

// New crée le Handler et initialise tous les services.
func New(db *sql.DB, hub *appws.Hub) *Handler {
	return &Handler{
		db:        db,
		users:     services.NewUserService(db),
		auth:      services.NewAuthService(db),
		likes:     services.NewLikeService(db),
		playlists: services.NewPlaylistService(db),
		friends:   services.NewFriendService(db),
		sessions:  services.NewSessionService(db),
		hub:       hub,
	}
}

// parseID lit un paramètre d'URL comme entier et écrit un 400 si invalide.
// Retourne (id, true) en cas de succès, (0, false) sinon.
func parseID(c *gin.Context, param string) (int, bool) {
	id, err := strconv.Atoi(c.Param(param))
	if err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: "invalid " + param})
		return 0, false
	}
	return id, true
}
