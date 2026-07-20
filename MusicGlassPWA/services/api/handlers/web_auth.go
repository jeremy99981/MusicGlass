package handlers

import (
	"app/services"
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

type webLoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=8"`
}
type webSignupRequest struct {
	Name     string `json:"name" binding:"required,min=2,max=255"`
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=8,max=128"`
}
type webRefreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

// respondAuthSuccess pose les cookies de session et renvoie la charge utile
// d'authentification commune à WebLogin, WebSignup et WebRefresh.
func respondAuthSuccess(c *gin.Context, status int, access, refresh string) {
	csrf := setWebCookies(c, access, refresh)
	c.JSON(status, gin.H{"authenticated": true, "csrf_token": csrf, "access_token": access, "refresh_token": refresh})
}

func (h *Handler) WebLogin(c *gin.Context) {
	var req webLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}
	access, refresh, err := h.auth.Login(req.Email, req.Password)
	if err != nil {
		if err == services.ErrInvalidCredentials {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
			return
		}
		internalError(c, err)
		return
	}
	respondAuthSuccess(c, http.StatusOK, access, refresh)
}

func (h *Handler) WebSignup(c *gin.Context) {
	var req webSignupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}
	if _, err := h.users.Create(req.Name, req.Email, req.Password); err != nil {
		if errors.Is(err, services.ErrEmailAlreadyExists) {
			c.JSON(http.StatusConflict, gin.H{"error": "email already exists"})
			return
		}
		internalError(c, err)
		return
	}
	access, refresh, err := h.auth.Login(req.Email, req.Password)
	if err != nil {
		internalError(c, err)
		return
	}
	respondAuthSuccess(c, http.StatusCreated, access, refresh)
}

func (h *Handler) WebRefresh(c *gin.Context) {
	refresh, err := c.Cookie(refreshCookie)
	if err != nil || refresh == "" {
		var req webRefreshRequest
		if bindErr := c.ShouldBindJSON(&req); bindErr == nil {
			refresh = strings.TrimSpace(req.RefreshToken)
		}
	}
	if refresh == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing refresh token"})
		return
	}
	access, rotated, err := h.auth.Refresh(refresh)
	if err != nil {
		clearWebCookies(c)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid refresh token"})
		return
	}
	respondAuthSuccess(c, http.StatusOK, access, rotated)
}

func (h *Handler) WebLogout(c *gin.Context) {
	refresh, _ := c.Cookie(refreshCookie)
	if err := h.auth.RevokeRefreshToken(refresh); err != nil {
		internalError(c, err)
		return
	}
	clearWebCookies(c)
	c.Status(http.StatusNoContent)
}

func (h *Handler) WebRevokeAll(c *gin.Context) {
	if err := h.auth.RevokeAll(c.GetInt("user_id")); err != nil {
		internalError(c, err)
		return
	}
	clearWebCookies(c)
	c.Status(http.StatusNoContent)
}

func (h *Handler) WebMe(c *gin.Context) {
	userID := c.GetInt("user_id")
	var name, email string
	if err := h.db.QueryRow(`SELECT name, email FROM users WHERE id=$1`, userID).Scan(&name, &email); err != nil {
		internalError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"id": userID, "name": name, "email": email})
}
