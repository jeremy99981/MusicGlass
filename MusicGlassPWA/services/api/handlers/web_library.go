package handlers

import (
	"app/services"
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
)

func (h *Handler) WebLibrary(c *gin.Context) {
	userID := c.GetInt("user_id")
	likes, err := h.likes.GetUserLikes(userID)
	if err != nil {
		internalError(c, err)
		return
	}
	playlists, err := h.playlists.ListByUser(userID)
	if err != nil {
		internalError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"likes":     likes,
		"playlists": playlists,
		"provider":  h.youtubeProviderPayload(userID),
	})
}

func (h *Handler) WebLibraryLikes(c *gin.Context) {
	likes, err := h.likes.GetUserLikes(c.GetInt("user_id"))
	if err != nil {
		internalError(c, err)
		return
	}
	c.JSON(http.StatusOK, likes)
}

func (h *Handler) WebLibraryAddLike(c *gin.Context) {
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

func (h *Handler) WebLibraryRemoveLike(c *gin.Context) {
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

func (h *Handler) WebLibraryPlaylists(c *gin.Context) {
	playlists, err := h.playlists.ListByUser(c.GetInt("user_id"))
	if err != nil {
		internalError(c, err)
		return
	}
	c.JSON(http.StatusOK, playlists)
}

func (h *Handler) WebLibraryCreatePlaylist(c *gin.Context) {
	var req CreatePlaylistRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}
	playlist, err := h.playlists.Create(c.GetInt("user_id"), services.CreatePlaylistInput{
		Name:        req.Name,
		Description: req.Description,
	})
	if err != nil {
		internalError(c, err)
		return
	}
	c.JSON(http.StatusCreated, playlist)
}

func (h *Handler) WebLibraryAddSongToPlaylist(c *gin.Context) {
	playlistID, ok := parseID(c, "playlist_id")
	if !ok {
		return
	}
	var req SongRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}
	song, err := h.playlists.AddSong(c.GetInt("user_id"), playlistID, req.toServiceInput())
	if err != nil {
		switch {
		case errors.Is(err, services.ErrPlaylistNotFound):
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "playlist not found"})
		case errors.Is(err, services.ErrSongAlreadyInList):
			c.JSON(http.StatusConflict, ErrorResponse{Error: "song already in playlist"})
		default:
			internalError(c, err)
		}
		return
	}
	c.JSON(http.StatusCreated, song)
}
