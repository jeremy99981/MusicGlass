package handlers

import (
	"log"
	"net/http"
	"os"
	"strings"

	"app/services"
	appws "app/ws"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	// CheckOrigin valide que l'origine de la requête est autorisée.
	// En production, restreindre à CORS_ALLOWED_ORIGINS.
	CheckOrigin: func(r *http.Request) bool {
		origin := r.Header.Get("Origin")
		// Les clients mobiles natifs n'envoient pas toujours Origin. Ils sont
		// authentifiés par JWT avant l'upgrade et ne sont pas soumis au modèle
		// de sécurité same-origin des navigateurs.
		if origin == "" {
			return true
		}
		allowed := os.Getenv("CORS_ALLOWED_ORIGINS")
		if allowed == "" {
			return true // dev : accepter tout
		}
		for _, o := range strings.Split(allowed, ",") {
			if strings.TrimSpace(o) == origin {
				return true
			}
		}
		return false
	},
}

// ServeWS godoc
// @Summary Rejoindre une session d'écoute via WebSocket
// @Description Connexion WebSocket pour la synchronisation musicale en temps réel.
// @Description Le JWT doit être passé en query param : ?token=<access_token>
// @Description
// @Description Messages envoyés par le client (hôte uniquement pour play/pause/seek/next) :
// @Description   {"type":"play","payload":{"song":{"external_id":"...","title":"...","artist":"..."},"position_ms":0}}
// @Description   {"type":"pause","payload":{"position_ms":12345}}
// @Description   {"type":"seek","payload":{"position_ms":30000}}
// @Description   {"type":"next","payload":{"song":{...},"position_ms":0}}
// @Description
// @Description Messages reçus par tous les clients :
// @Description   {"type":"state","payload":{"song":{...},"is_playing":true,"position_ms":0,"updated_at":"...","participants":[...]}}
// @Description   {"type":"play","sender_id":1,"payload":{...}}
// @Description   {"type":"joined","payload":{"user_id":2,"name":"Bob"}}
// @Description   {"type":"left","payload":{"user_id":2,"name":"Bob"}}
// @Description   {"type":"host_left"}
// @Description   {"type":"error","payload":{"message":"..."}}
// @Tags sessions
// @Param code  path  string true "Code de la session"
// @Param token query string true "JWT access token"
// @Router /ws/{code} [get]
func (h *Handler) ServeWS(c *gin.Context) {
	// 1. Valider le JWT (passé en query param car le browser WebSocket API
	//    ne supporte pas les headers custom lors de l'upgrade).
	tokenStr := c.Query("token")
	if tokenStr == "" {
		c.JSON(http.StatusUnauthorized, ErrorResponse{Error: "missing token"})
		return
	}

	claims, err := services.ParseAccessToken(tokenStr)
	if err != nil {
		c.JSON(http.StatusUnauthorized, ErrorResponse{Error: "invalid token"})
		return
	}

	// 2. Vérifier que la session existe et est active.
	code := strings.ToUpper(c.Param("code"))
	sess, err := h.sessions.GetByCode(code)
	if err != nil {
		c.JSON(http.StatusNotFound, ErrorResponse{Error: "session not found"})
		return
	}

	// 3. Récupérer le nom de l'utilisateur pour les annonces de room.
	user, err := h.users.GetByID(claims.UserID)
	if err != nil {
		internalError(c, err)
		return
	}

	// 4. Upgrade HTTP → WebSocket.
	requestedRole := strings.ToLower(strings.TrimSpace(c.Query("role")))
	isHost := requestedRole == "host" && claims.UserID == sess.HostID
	if requestedRole == "" {
		isHost = claims.UserID == sess.HostID
	}
	clientID := strings.TrimSpace(c.Query("client_id"))

	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("[WS] upgrade error user=%d: %v", claims.UserID, err)
		return
	}

	// 5. Créer le client et le rejoindre à la room.
	client := appws.NewClient(h.hub, claims.UserID, user.Name, clientID, isHost, conn)
	h.hub.Join(code, client, sess.HostID)
}
