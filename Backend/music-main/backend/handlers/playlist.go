package handlers

import (
	"errors"
	"net/http"

	"app/services"

	"github.com/gin-gonic/gin"
)

// ListPlaylists godoc
// @Summary Liste les playlists de l'utilisateur
// @Description Retourne uniquement les playlists de l'utilisateur authentifié, avec le nombre de musiques.
// @Tags playlists
// @Produce json
// @Param user_id path int true "ID de l'utilisateur"
// @Success 200 {array} services.PlaylistSummary
// @Failure 401 {object} ErrorResponse
// @Failure 403 {object} ErrorResponse
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /users/{user_id}/playlists [get]
func (h *Handler) ListPlaylists(c *gin.Context) {
	summaries, err := h.playlists.ListByUser(c.GetInt("user_id"))
	if err != nil {
		internalError(c, err)
		return
	}
	c.JSON(http.StatusOK, summaries)
}

// CreatePlaylist godoc
// @Summary Crée une playlist (privée par défaut)
// @Tags playlists
// @Accept json
// @Produce json
// @Param user_id path int true "ID de l'utilisateur"
// @Param request body CreatePlaylistRequest true "Données de la playlist"
// @Success 201 {object} services.Playlist
// @Failure 400 {object} ErrorResponse
// @Failure 401 {object} ErrorResponse
// @Failure 403 {object} ErrorResponse
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /users/{user_id}/playlists [post]
func (h *Handler) CreatePlaylist(c *gin.Context) {
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

// GetPlaylist godoc
// @Summary Récupère une playlist avec ses musiques
// @Tags playlists
// @Produce json
// @Param user_id     path int true "ID de l'utilisateur"
// @Param playlist_id path int true "ID de la playlist"
// @Success 200 {object} services.Playlist
// @Failure 401 {object} ErrorResponse
// @Failure 403 {object} ErrorResponse
// @Failure 404 {object} ErrorResponse
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /users/{user_id}/playlists/{playlist_id} [get]
func (h *Handler) GetPlaylist(c *gin.Context) {
	playlistID, ok := parseID(c, "playlist_id")
	if !ok {
		return
	}

	playlist, err := h.playlists.GetByID(c.GetInt("user_id"), playlistID)
	if err != nil {
		if errors.Is(err, services.ErrPlaylistNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "playlist not found"})
			return
		}
		internalError(c, err)
		return
	}
	c.JSON(http.StatusOK, playlist)
}

// UpdatePlaylist godoc
// @Summary Met à jour une playlist (nom, description, visibilité)
// @Description Tous les champs sont optionnels. Seuls les champs fournis sont modifiés.
// @Tags playlists
// @Accept json
// @Produce json
// @Param user_id     path int true "ID de l'utilisateur"
// @Param playlist_id path int true "ID de la playlist"
// @Param request body UpdatePlaylistRequest true "Champs à mettre à jour"
// @Success 200 {object} services.PlaylistSummary
// @Failure 400 {object} ErrorResponse
// @Failure 401 {object} ErrorResponse
// @Failure 403 {object} ErrorResponse
// @Failure 404 {object} ErrorResponse
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /users/{user_id}/playlists/{playlist_id} [patch]
func (h *Handler) UpdatePlaylist(c *gin.Context) {
	playlistID, ok := parseID(c, "playlist_id")
	if !ok {
		return
	}

	var req UpdatePlaylistRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}

	summary, err := h.playlists.Update(c.GetInt("user_id"), playlistID, services.UpdatePlaylistInput{
		Name:        req.Name,
		Description: req.Description,
		IsPublic:    req.IsPublic,
	})
	if err != nil {
		switch {
		case errors.Is(err, services.ErrNoFieldsToUpdate):
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "no fields to update"})
		case errors.Is(err, services.ErrPlaylistNotFound):
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "playlist not found"})
		default:
			internalError(c, err)
		}
		return
	}
	c.JSON(http.StatusOK, summary)
}

// DeletePlaylist godoc
// @Summary Supprime une playlist
// @Tags playlists
// @Produce json
// @Param user_id     path int true "ID de l'utilisateur"
// @Param playlist_id path int true "ID de la playlist"
// @Success 204 "No Content"
// @Failure 401 {object} ErrorResponse
// @Failure 403 {object} ErrorResponse
// @Failure 404 {object} ErrorResponse
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /users/{user_id}/playlists/{playlist_id} [delete]
func (h *Handler) DeletePlaylist(c *gin.Context) {
	playlistID, ok := parseID(c, "playlist_id")
	if !ok {
		return
	}

	if err := h.playlists.Delete(c.GetInt("user_id"), playlistID); err != nil {
		if errors.Is(err, services.ErrPlaylistNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "playlist not found"})
			return
		}
		internalError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

// AddSongToPlaylist godoc
// @Summary Ajoute une musique à une playlist
// @Description La musique est insérée dans le référentiel partagé si elle n'existe pas encore.
// @Tags playlists
// @Accept json
// @Produce json
// @Param user_id     path int true "ID de l'utilisateur"
// @Param playlist_id path int true "ID de la playlist"
// @Param request body SongRequest true "Métadonnées de la musique"
// @Success 201 {object} services.PlaylistSong
// @Failure 400 {object} ErrorResponse
// @Failure 401 {object} ErrorResponse
// @Failure 403 {object} ErrorResponse
// @Failure 404 {object} ErrorResponse
// @Failure 409 {object} ErrorResponse "Musique déjà dans la playlist"
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /users/{user_id}/playlists/{playlist_id}/songs [post]
func (h *Handler) AddSongToPlaylist(c *gin.Context) {
	playlistID, ok := parseID(c, "playlist_id")
	if !ok {
		return
	}

	var req SongRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}

	entry, err := h.playlists.AddSong(c.GetInt("user_id"), playlistID, req.toServiceInput())
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
	c.JSON(http.StatusCreated, entry)
}

// RemoveSongFromPlaylist godoc
// @Summary Retire une musique d'une playlist
// @Tags playlists
// @Produce json
// @Param user_id     path int true "ID de l'utilisateur"
// @Param playlist_id path int true "ID de la playlist"
// @Param entry_id    path int true "ID de l'entrée (entry_id retourné lors de l'ajout)"
// @Success 204 "No Content"
// @Failure 401 {object} ErrorResponse
// @Failure 403 {object} ErrorResponse
// @Failure 404 {object} ErrorResponse
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /users/{user_id}/playlists/{playlist_id}/songs/{entry_id} [delete]
func (h *Handler) RemoveSongFromPlaylist(c *gin.Context) {
	playlistID, ok := parseID(c, "playlist_id")
	if !ok {
		return
	}
	entryID, ok := parseID(c, "entry_id")
	if !ok {
		return
	}

	if err := h.playlists.RemoveSong(c.GetInt("user_id"), playlistID, entryID); err != nil {
		if errors.Is(err, services.ErrEntryNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "entry not found"})
			return
		}
		internalError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}
