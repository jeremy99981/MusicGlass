package handlers

import (
	"errors"
	"net/http"

	"app/services"

	"github.com/gin-gonic/gin"
)

// ListLikes godoc
// @Summary Liste les musiques likées par l'utilisateur
// @Description Retourne uniquement les likes de l'utilisateur authentifié. Privé par défaut.
// @Tags likes
// @Produce json
// @Param user_id path int true "ID de l'utilisateur"
// @Success 200 {array} services.Like
// @Failure 401 {object} ErrorResponse
// @Failure 403 {object} ErrorResponse
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /users/{user_id}/likes [get]
func (h *Handler) ListLikes(c *gin.Context) {
	likes, err := h.likes.GetUserLikes(c.GetInt("user_id"))
	if err != nil {
		internalError(c, err)
		return
	}
	c.JSON(http.StatusOK, likes)
}

// AddLike godoc
// @Summary Like une musique (privé par défaut)
// @Description Ajoute la musique aux favoris. La musique est créée si elle n'existe pas encore.
// @Tags likes
// @Accept json
// @Produce json
// @Param user_id path int true "ID de l'utilisateur"
// @Param request body SongRequest true "Métadonnées de la musique à liker"
// @Success 201 {object} services.Like
// @Failure 400 {object} ErrorResponse
// @Failure 401 {object} ErrorResponse
// @Failure 403 {object} ErrorResponse
// @Failure 409 {object} ErrorResponse "Musique déjà likée"
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /users/{user_id}/likes [post]
func (h *Handler) AddLike(c *gin.Context) {
	var req SongRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}

	like, err := h.likes.AddLike(c.GetInt("user_id"), req.toServiceInput())
	if err != nil {
		if errors.Is(err, services.ErrAlreadyLiked) {
			c.JSON(http.StatusConflict, ErrorResponse{Error: "song already liked"})
			return
		}
		internalError(c, err)
		return
	}
	c.JSON(http.StatusCreated, like)
}

// RemoveLike godoc
// @Summary Retire un like
// @Tags likes
// @Produce json
// @Param user_id path int true "ID de l'utilisateur"
// @Param like_id path int true "ID du like"
// @Success 204 "No Content"
// @Failure 401 {object} ErrorResponse
// @Failure 403 {object} ErrorResponse
// @Failure 404 {object} ErrorResponse
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /users/{user_id}/likes/{like_id} [delete]
func (h *Handler) RemoveLike(c *gin.Context) {
	likeID, ok := parseID(c, "like_id")
	if !ok {
		return
	}

	if err := h.likes.RemoveLike(c.GetInt("user_id"), likeID); err != nil {
		if errors.Is(err, services.ErrLikeNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "like not found"})
			return
		}
		internalError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

// SetLikeVisibility godoc
// @Summary Change la visibilité d'un like (public / privé)
// @Tags likes
// @Accept json
// @Produce json
// @Param user_id path int true "ID de l'utilisateur"
// @Param like_id path int true "ID du like"
// @Param request body SetLikeVisibilityRequest true "Nouvelle visibilité"
// @Success 200 {object} services.Like
// @Failure 400 {object} ErrorResponse
// @Failure 401 {object} ErrorResponse
// @Failure 403 {object} ErrorResponse
// @Failure 404 {object} ErrorResponse
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /users/{user_id}/likes/{like_id} [patch]
func (h *Handler) SetLikeVisibility(c *gin.Context) {
	likeID, ok := parseID(c, "like_id")
	if !ok {
		return
	}

	var req SetLikeVisibilityRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}

	like, err := h.likes.SetLikeVisibility(c.GetInt("user_id"), likeID, *req.IsPublic)
	if err != nil {
		if errors.Is(err, services.ErrLikeNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "like not found"})
			return
		}
		internalError(c, err)
		return
	}
	c.JSON(http.StatusOK, like)
}
