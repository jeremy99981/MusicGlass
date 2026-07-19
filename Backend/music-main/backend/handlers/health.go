package handlers

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
)

// Health godoc
// @Summary Vérifie l'état du service
// @Description Vérifie que l'API et la base PostgreSQL sont accessibles
// @Tags health
// @Produce json
// @Success 200 {object} HealthResponse
// @Failure 503 {object} HealthResponse
// @Router /health [get]
func (h *Handler) Health(c *gin.Context) {
	if err := h.db.Ping(); err != nil {
		log.Printf("[ERROR] health check — db ping: %v", err)
		c.JSON(http.StatusServiceUnavailable, HealthResponse{Status: "unhealthy"})
		return
	}
	c.JSON(http.StatusOK, HealthResponse{Status: "ok"})
}
