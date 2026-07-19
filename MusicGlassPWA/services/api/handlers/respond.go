package handlers

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
)

// internalError logue l'erreur complète côté serveur et retourne un message
// générique au client. Ne jamais exposer err.Error() directement : les messages
// d'erreur PostgreSQL ou Go peuvent contenir des noms de tables, de colonnes,
// ou des détails internes exploitables par un attaquant.
func internalError(c *gin.Context, err error) {
	log.Printf("[ERROR] %s %s — %v", c.Request.Method, c.Request.URL.Path, err)
	c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "internal server error"})
}
