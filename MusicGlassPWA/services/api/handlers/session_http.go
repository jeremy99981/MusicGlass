package handlers

import (
	"errors"
	"net/http"

	"app/services"

	"github.com/gin-gonic/gin"
)

// CreateSession godoc
// @Summary Crée une session d'écoute partagée
// @Description Retourne un code à 8 caractères à partager avec les amis.
// @Tags sessions
// @Produce json
// @Success 201 {object} services.ListenSession
// @Failure 401 {object} ErrorResponse
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /sessions [post]
func (h *Handler) CreateSession(c *gin.Context) {
	sess, err := h.sessions.Create(c.GetInt("user_id"))
	if err != nil {
		internalError(c, err)
		return
	}
	c.JSON(http.StatusCreated, sess)
}

// GetSession godoc
// @Summary Récupère les informations d'une session active
// @Tags sessions
// @Produce json
// @Param code path string true "Code de la session (8 caractères)"
// @Success 200 {object} services.ListenSession
// @Failure 401 {object} ErrorResponse
// @Failure 404 {object} ErrorResponse
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /sessions/{code} [get]
func (h *Handler) GetSession(c *gin.Context) {
	sess, err := h.sessions.GetByCode(c.Param("code"))
	if err != nil {
		if errors.Is(err, services.ErrSessionNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "session not found"})
			return
		}
		internalError(c, err)
		return
	}
	c.JSON(http.StatusOK, sess)
}

// EndSession godoc
// @Summary Termine une session (hôte uniquement)
// @Description Marque la session inactive et déconnecte tous les participants WebSocket.
// @Tags sessions
// @Produce json
// @Param code path string true "Code de la session"
// @Success 204 "No Content"
// @Failure 401 {object} ErrorResponse
// @Failure 404 {object} ErrorResponse "Session introuvable ou n'appartient pas à cet utilisateur"
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /sessions/{code} [delete]
func (h *Handler) EndSession(c *gin.Context) {
	code := c.Param("code")

	if err := h.sessions.End(c.GetInt("user_id"), code); err != nil {
		if errors.Is(err, services.ErrSessionNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "session not found"})
			return
		}
		internalError(c, err)
		return
	}

	// Déconnecte proprement tous les clients WebSocket de cette room.
	h.hub.CloseRoom(code)

	c.Status(http.StatusNoContent)
}
