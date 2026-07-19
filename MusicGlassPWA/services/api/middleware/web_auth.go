package middleware

import (
	"crypto/subtle"
	"net/http"
	"strings"

	"app/services"
	"github.com/gin-gonic/gin"
)

const AccessCookie = "mg_access"
const CSRFCookie = "mg_csrf"

func WebAuthRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		token, err := c.Cookie(AccessCookie)
		if err != nil || token == "" {
			authorization := c.GetHeader("Authorization")
			if strings.HasPrefix(authorization, "Bearer ") {
				token = strings.TrimSpace(strings.TrimPrefix(authorization, "Bearer "))
			}
		}
		claims, err := services.ParseAccessToken(token)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
			return
		}
		c.Set("user_id", claims.UserID)
		c.Next()
	}
}

func CSRFRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.Request.Method == http.MethodGet || c.Request.Method == http.MethodHead || c.Request.Method == http.MethodOptions {
			c.Next()
			return
		}
		// Bearer-authenticated clients are not vulnerable to cookie-based CSRF.
		// This also lets a separately hosted PWA work when Safari blocks third-party cookies.
		if strings.HasPrefix(c.GetHeader("Authorization"), "Bearer ") {
			c.Next()
			return
		}
		cookie, err := c.Cookie(CSRFCookie)
		header := c.GetHeader("X-CSRF-Token")
		if err != nil || cookie == "" || header == "" || subtle.ConstantTimeCompare([]byte(cookie), []byte(header)) != 1 {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "invalid csrf token"})
			return
		}
		c.Next()
	}
}
