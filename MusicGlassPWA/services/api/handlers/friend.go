package handlers

import (
	"errors"
	"net/http"

	"app/services"

	"github.com/gin-gonic/gin"
)

// ListFriends godoc
// @Summary Liste les amis de l'utilisateur
// @Tags friends
// @Produce json
// @Param user_id path int true "ID de l'utilisateur"
// @Success 200 {array} services.FriendInfo
// @Failure 401 {object} ErrorResponse
// @Failure 403 {object} ErrorResponse
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /users/{user_id}/friends [get]
func (h *Handler) ListFriends(c *gin.Context) {
	friends, err := h.friends.ListFriends(c.GetInt("user_id"))
	if err != nil {
		internalError(c, err)
		return
	}
	c.JSON(http.StatusOK, friends)
}

// ListFriendRequests godoc
// @Summary Liste les demandes d'amitié reçues en attente
// @Tags friends
// @Produce json
// @Param user_id path int true "ID de l'utilisateur"
// @Success 200 {array} services.Friendship
// @Failure 401 {object} ErrorResponse
// @Failure 403 {object} ErrorResponse
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /users/{user_id}/friends/requests [get]
func (h *Handler) ListFriendRequests(c *gin.Context) {
	requests, err := h.friends.ListPendingRequests(c.GetInt("user_id"))
	if err != nil {
		internalError(c, err)
		return
	}
	c.JSON(http.StatusOK, requests)
}

// SendFriendRequest godoc
// @Summary Envoie une demande d'amitié
// @Tags friends
// @Accept json
// @Produce json
// @Param user_id path int true "ID de l'utilisateur"
// @Param request body SendFriendRequestBody true "ID du destinataire"
// @Success 201 {object} services.Friendship
// @Failure 400 {object} ErrorResponse
// @Failure 401 {object} ErrorResponse
// @Failure 403 {object} ErrorResponse
// @Failure 409 {object} ErrorResponse "Demande déjà existante"
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /users/{user_id}/friends/requests [post]
func (h *Handler) SendFriendRequest(c *gin.Context) {
	var req SendFriendRequestBody
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}

	friendship, err := h.friends.SendRequest(c.GetInt("user_id"), req.AddresseeID)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrCannotFriendYourself):
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "cannot send friend request to yourself"})
		case errors.Is(err, services.ErrAlreadyFriends):
			c.JSON(http.StatusConflict, ErrorResponse{Error: "friendship already exists"})
		default:
			internalError(c, err)
		}
		return
	}
	c.JSON(http.StatusCreated, friendship)
}

// AcceptFriendRequest godoc
// @Summary Accepte une demande d'amitié
// @Tags friends
// @Produce json
// @Param user_id    path int true "ID de l'utilisateur"
// @Param request_id path int true "ID de la demande"
// @Success 200 {object} services.Friendship
// @Failure 401 {object} ErrorResponse
// @Failure 403 {object} ErrorResponse
// @Failure 404 {object} ErrorResponse
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /users/{user_id}/friends/requests/{request_id}/accept [post]
func (h *Handler) AcceptFriendRequest(c *gin.Context) {
	requestID, ok := parseID(c, "request_id")
	if !ok {
		return
	}

	friendship, err := h.friends.AcceptRequest(c.GetInt("user_id"), requestID)
	if err != nil {
		if errors.Is(err, services.ErrFriendRequestNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "friend request not found"})
			return
		}
		internalError(c, err)
		return
	}
	c.JSON(http.StatusOK, friendship)
}

// DeclineFriendRequest godoc
// @Summary Refuse ou annule une demande d'amitié
// @Tags friends
// @Produce json
// @Param user_id    path int true "ID de l'utilisateur"
// @Param request_id path int true "ID de la demande"
// @Success 204 "No Content"
// @Failure 401 {object} ErrorResponse
// @Failure 403 {object} ErrorResponse
// @Failure 404 {object} ErrorResponse
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /users/{user_id}/friends/requests/{request_id} [delete]
func (h *Handler) DeclineFriendRequest(c *gin.Context) {
	requestID, ok := parseID(c, "request_id")
	if !ok {
		return
	}

	if err := h.friends.DeclineRequest(c.GetInt("user_id"), requestID); err != nil {
		if errors.Is(err, services.ErrFriendRequestNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "friend request not found"})
			return
		}
		internalError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

// RemoveFriend godoc
// @Summary Supprime un ami
// @Tags friends
// @Produce json
// @Param user_id   path int true "ID de l'utilisateur"
// @Param friend_id path int true "ID de l'ami à supprimer"
// @Success 204 "No Content"
// @Failure 401 {object} ErrorResponse
// @Failure 403 {object} ErrorResponse
// @Failure 404 {object} ErrorResponse
// @Failure 500 {object} ErrorResponse
// @Security BearerAuth
// @Router /users/{user_id}/friends/{friend_id} [delete]
func (h *Handler) RemoveFriend(c *gin.Context) {
	friendID, ok := parseID(c, "friend_id")
	if !ok {
		return
	}

	if err := h.friends.RemoveFriend(c.GetInt("user_id"), friendID); err != nil {
		if errors.Is(err, services.ErrFriendRequestNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "friend not found"})
			return
		}
		internalError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}
