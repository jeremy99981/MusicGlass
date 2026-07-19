package handlers

import (
	"errors"
	"net/http"

	"app/services"

	"github.com/gin-gonic/gin"
)

// GetProfile godoc
// @Summary Récupère le profil de l'utilisateur connecté
// @Tags users
// @Produce json
// @Param user_id path int true "ID de l'utilisateur"
// @Success 200 {object} services.User
// @Failure 401 {object} ErrorResponse
// @Failure 403 {object} ErrorResponse
// @Failure 404 {object} ErrorResponse
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /users/{user_id}/profile [get]
func (h *Handler) GetProfile(c *gin.Context) {
	user, err := h.users.GetByID(c.GetInt("user_id"))
	if err != nil {
		if errors.Is(err, services.ErrUserNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "user not found"})
			return
		}
		internalError(c, err)
		return
	}
	c.JSON(http.StatusOK, user)
}

// UpdateProfile godoc
// @Summary Met à jour le profil de l'utilisateur connecté
// @Tags users
// @Accept json
// @Produce json
// @Param user_id path int true "ID de l'utilisateur"
// @Param request body UpdateProfileRequest true "Champs à mettre à jour (tous optionnels)"
// @Success 200 {object} services.User
// @Failure 400 {object} ErrorResponse
// @Failure 401 {object} ErrorResponse
// @Failure 403 {object} ErrorResponse
// @Failure 409 {object} ErrorResponse
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /users/{user_id}/profile [patch]
func (h *Handler) UpdateProfile(c *gin.Context) {
	var req UpdateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}

	user, err := h.users.UpdateProfile(c.GetInt("user_id"), services.UpdateProfileInput{
		FirstName: req.FirstName,
		LastName:  req.LastName,
		Email:     req.Email,
	})
	if err != nil {
		switch {
		case errors.Is(err, services.ErrNoFieldsToUpdate):
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "no fields to update"})
		case errors.Is(err, services.ErrEmailAlreadyExists):
			c.JSON(http.StatusConflict, ErrorResponse{Error: "email already in use"})
		case errors.Is(err, services.ErrUserNotFound):
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "user not found"})
		default:
			internalError(c, err)
		}
		return
	}
	c.JSON(http.StatusOK, user)
}
