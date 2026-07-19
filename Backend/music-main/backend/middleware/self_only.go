package middleware

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

// SelfOnly garantit qu'un utilisateur authentifié ne peut accéder qu'à ses propres ressources.
// Doit être utilisé après AuthRequired (qui injecte "user_id" dans le contexte).
// Protège contre les attaques IDOR en comparant le paramètre d'URL :user_id avec le user_id du JWT.
func SelfOnly() gin.HandlerFunc {
	return func(c *gin.Context) {
		jwtUserID, exists := c.Get("user_id")
		if !exists {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
			return
		}

		paramUserID, err := strconv.Atoi(c.Param("user_id"))
		if err != nil {
			c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{"error": "invalid user_id parameter"})
			return
		}

		if jwtUserID.(int) != paramUserID {
			// Volontairement générique pour ne pas révéler l'existence d'autres utilisateurs.
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "access denied"})
			return
		}

		c.Next()
	}
}
