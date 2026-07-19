package middleware

import (
	"strings"

	"github.com/gin-gonic/gin"
)

// SecurityHeaders ajoute les en-têtes HTTP de sécurité standard sur toutes les réponses.
// À appliquer en premier middleware global, avant les routes.
func SecurityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Empêche le navigateur d'interpréter un Content-Type différent de celui déclaré.
		c.Header("X-Content-Type-Options", "nosniff")

		// Bloque l'intégration de cette API dans une iframe (protection clickjacking).
		c.Header("X-Frame-Options", "DENY")

		// Limite les informations envoyées dans l'en-tête Referer.
		c.Header("Referrer-Policy", "strict-origin-when-cross-origin")

		// Politique CSP stricte pour l'API JSON.
		csp := "default-src 'none'"
		// Swagger UI charge des assets JS/CSS/images depuis la même origine.
		if strings.HasPrefix(c.Request.URL.Path, "/swagger/") {
			csp = "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; font-src 'self' data:"
		}
		c.Header("Content-Security-Policy", csp)

		// Les réponses API ne doivent jamais être mises en cache (données sensibles).
		c.Header("Cache-Control", "no-store")

		// Désactive les fonctionnalités navigateur non nécessaires pour une API.
		c.Header("Permissions-Policy", "camera=(), microphone=(), geolocation=()")

		c.Next()
	}
}
