package handlers

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

type searchHistoryRequest struct {
	Query string `json:"query" binding:"required,max=160"`
}

func (h *Handler) WebSearchHistory(c *gin.Context) {
	entries, err := h.searches.List(c.GetInt("user_id"))
	if err != nil {
		internalError(c, err)
		return
	}
	c.JSON(http.StatusOK, entries)
}

func (h *Handler) WebRecordSearch(c *gin.Context) {
	var request searchHistoryRequest
	if err := c.ShouldBindJSON(&request); err != nil || strings.TrimSpace(request.Query) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "search query is required"})
		return
	}
	entry, err := h.searches.Record(c.GetInt("user_id"), request.Query)
	if err != nil {
		internalError(c, err)
		return
	}
	c.JSON(http.StatusCreated, entry)
}

func (h *Handler) WebClearSearchHistory(c *gin.Context) {
	if err := h.searches.Clear(c.GetInt("user_id")); err != nil {
		internalError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}
