package ws

import (
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/gorilla/websocket"
)

const (
	writeWait  = 10 * time.Second    // délai max pour écrire un message
	pongWait   = 60 * time.Second    // délai max sans pong du client
	pingPeriod = (pongWait * 9) / 10 // fréquence des pings serveur
	// A full playback snapshot can contain several hundred queued tracks.
	// Keep a finite limit, but leave enough room for that initial synchronization.
	maxMessageSize = 1 << 20 // 1 MiB
	sendBuffer     = 256     // taille du canal d'envoi par client
)

// Client représente une connexion WebSocket d'un participant.
type Client struct {
	hub      *Hub
	room     *Room
	userID   int
	name     string
	clientID string
	isHost   bool
	conn     *websocket.Conn
	send     chan []byte
}

// NewClient crée un client prêt à être rejoint à une room.
func NewClient(hub *Hub, userID int, name, clientID string, isHost bool, conn *websocket.Conn) *Client {
	if clientID == "" {
		clientID = fmt.Sprintf("%d-%d", userID, time.Now().UnixNano())
	}
	return &Client{
		hub:      hub,
		userID:   userID,
		name:     name,
		clientID: clientID,
		isHost:   isHost,
		conn:     conn,
		send:     make(chan []byte, sendBuffer),
	}
}

// sendMsg sérialise et enfile un message dans le canal d'envoi.
func (c *Client) sendMsg(msg Outgoing) {
	select {
	case c.send <- encode(msg):
	default:
		// Canal plein : client trop lent. On ferme la connexion.
		c.conn.Close()
	}
}

// readPump lit les messages du WebSocket et les transmet à la room.
// Doit tourner dans sa propre goroutine.
func (c *Client) readPump() {
	defer func() {
		c.room.leave(c)
		close(c.send)
		c.conn.Close()
	}()

	c.conn.SetReadLimit(maxMessageSize)
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, data, err := c.conn.ReadMessage()
		if err != nil {
			log.Printf("[WS] client=%s user=%d disconnected: %v", c.clientID, c.userID, err)
			return
		}

		var msg Incoming
		if err := json.Unmarshal(data, &msg); err != nil {
			c.sendMsg(Outgoing{
				Type:    TypeError,
				Payload: map[string]string{"message": "invalid JSON"},
			})
			continue
		}

		c.room.handleMessage(c, msg)
	}
}

// writePump écrit les messages depuis le canal send vers le WebSocket.
// Envoie des pings périodiques pour maintenir la connexion vivante.
// Doit tourner dans sa propre goroutine.
func (c *Client) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case msg, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				// Canal fermé : envoyer un close frame et sortir.
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}

		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
