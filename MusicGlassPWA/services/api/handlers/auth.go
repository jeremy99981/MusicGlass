package handlers

import (
	"errors"
	"net/http"

	"app/services"

	"github.com/gin-gonic/gin"
)

// Signup godoc
// @Summary Crée un compte utilisateur
// @Tags auth
// @Accept json
// @Produce json
// @Param request body SignupRequest true "Payload signup"
// @Success 201 {object} services.User
// @Failure 400 {object} ErrorResponse
// @Failure 409 {object} ErrorResponse
// @Failure 500 {object} ErrorResponse
// @Router /auth/signup [post]
func (h *Handler) Signup(c *gin.Context) {
	var req SignupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}

	user, err := h.users.Create(req.Name, req.Email, req.Password)
	if err != nil {
		if errors.Is(err, services.ErrEmailAlreadyExists) {
			c.JSON(http.StatusConflict, ErrorResponse{Error: "email already exists"})
			return
		}
		internalError(c, err)
		return
	}

	c.JSON(http.StatusCreated, user)
}

// Login godoc
// @Summary Connecte un utilisateur
// @Tags auth
// @Accept json
// @Produce json
// @Param request body LoginRequest true "Payload login"
// @Success 200 {object} AuthTokensResponse
// @Failure 400 {object} ErrorResponse
// @Failure 401 {object} ErrorResponse
// @Failure 500 {object} ErrorResponse
// @Router /auth/login [post]
func (h *Handler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}

	accessToken, refreshToken, err := h.auth.Login(req.Email, req.Password)
	if err != nil {
		if errors.Is(err, services.ErrInvalidCredentials) {
			c.JSON(http.StatusUnauthorized, ErrorResponse{Error: "invalid credentials"})
			return
		}
		internalError(c, err)
		return
	}

	c.JSON(http.StatusOK, AuthTokensResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		TokenType:    "Bearer",
	})
}

// Refresh godoc
// @Summary Renouvelle les tokens
// @Tags auth
// @Accept json
// @Produce json
// @Param request body RefreshRequest true "Payload refresh"
// @Success 200 {object} AuthTokensResponse
// @Failure 400 {object} ErrorResponse
// @Failure 401 {object} ErrorResponse
// @Failure 500 {object} ErrorResponse
// @Router /auth/refresh [post]
func (h *Handler) Refresh(c *gin.Context) {
	var req RefreshRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}

	accessToken, refreshToken, err := h.auth.Refresh(req.RefreshToken)
	if err != nil {
		if errors.Is(err, services.ErrInvalidRefreshToken) {
			c.JSON(http.StatusUnauthorized, ErrorResponse{Error: "invalid refresh token"})
			return
		}
		internalError(c, err)
		return
	}

	c.JSON(http.StatusOK, AuthTokensResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		TokenType:    "Bearer",
	})
}
