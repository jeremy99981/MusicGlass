package ws

import (
	"encoding/json"
	"sync"
	"time"
)

// Hub gère l'ensemble des rooms WebSocket actives.
// Thread-safe : tous les accès aux rooms passent par mu.
type Hub struct {
	mu    sync.RWMutex
	rooms map[string]*Room
}

func NewHub() *Hub {
	return &Hub{rooms: make(map[string]*Room)}
}

// Join ajoute client à la room identifiée par code.
// Si la room n'existe pas encore, elle est créée avec hostID comme hôte.
func (h *Hub) Join(code string, client *Client, hostID int) {
	h.mu.Lock()
	room, exists := h.rooms[code]
	if !exists {
		room = &Room{
			hub:     h,
			code:    code,
			hostID:  hostID,
			clients: make(map[*Client]struct{}),
		}
		h.rooms[code] = room
	}
	h.mu.Unlock()

	room.join(client)
}

// CloseRoom ferme tous les clients d'une room et la supprime.
// Appelé quand l'hôte termine la session via HTTP.
func (h *Hub) CloseRoom(code string) {
	h.mu.Lock()
	room, exists := h.rooms[code]
	if exists {
		delete(h.rooms, code)
	}
	h.mu.Unlock()

	if exists {
		room.closeAll()
	}
}

// RoomExists retourne true si une room active existe pour ce code.
func (h *Hub) RoomExists(code string) bool {
	h.mu.RLock()
	_, ok := h.rooms[code]
	h.mu.RUnlock()
	return ok
}

func (h *Hub) removeRoom(code string) {
	h.mu.Lock()
	delete(h.rooms, code)
	h.mu.Unlock()
}

// ── Room ──────────────────────────────────────────────────────────────────────

// Room représente une session d'écoute en cours avec ses participants.
type Room struct {
	hub    *Hub
	code   string
	hostID int

	mu      sync.RWMutex
	clients map[*Client]struct{}
	state   PlaybackState
}

// join inscrit le client dans la room et démarre ses goroutines.
func (r *Room) join(c *Client) {
	c.room = r

	r.mu.Lock()
	r.clients[c] = struct{}{}
	participants := r.participantListLocked()
	state := r.state
	r.mu.Unlock()

	// État courant envoyé immédiatement au nouveau participant.
	c.sendMsg(Outgoing{
		Type: TypeState,
		Payload: StatePayload{
			PlaybackState: state,
			Participants:  participants,
		},
	})

	// Annonce aux autres participants.
	r.broadcastExcept(c, Outgoing{
		Type:    TypeJoined,
		Payload: r.participantInfo(c),
	})

	go c.writePump()
	go c.readPump()
}

// leave retire le client de la room et notifie les autres.
func (r *Room) leave(c *Client) {
	r.mu.Lock()
	delete(r.clients, c)
	empty := len(r.clients) == 0
	hasHost := false
	for client := range r.clients {
		if client.isHost {
			hasHost = true
			break
		}
	}
	r.mu.Unlock()

	if !empty {
		if c.isHost && !hasHost {
			r.broadcastAll(Outgoing{Type: TypeHostLeft})
		} else {
			r.broadcastAll(Outgoing{
				Type:    TypeLeft,
				Payload: r.participantInfo(c),
			})
		}
	}

	if empty {
		r.hub.removeRoom(r.code)
	}
}

// handleMessage traite un message entrant d'un client.
// Seul l'hôte peut envoyer des commandes de lecture (play/pause/seek/next).
func (r *Room) handleMessage(sender *Client, msg Incoming) {
	switch msg.Type {
	case TypePlay, TypePause, TypeSeek, TypeNext, TypeSync:
		if !sender.isHost {
			sender.sendMsg(Outgoing{
				Type:    TypeError,
				Payload: map[string]string{"message": "only the host can control playback"},
			})
			return
		}
		r.updateState(msg)
		r.broadcastAll(Outgoing{
			Type:           msg.Type,
			SenderID:       sender.userID,
			SenderClientID: sender.clientID,
			Payload:        json.RawMessage(msg.Payload),
		})

	default:
		sender.sendMsg(Outgoing{
			Type:    TypeError,
			Payload: map[string]string{"message": "unknown message type"},
		})
	}
}

// updateState met à jour l'état du lecteur en fonction du message de l'hôte.
func (r *Room) updateState(msg Incoming) {
	r.mu.Lock()
	defer r.mu.Unlock()

	now := time.Now()
	switch msg.Type {
	case TypeSync:
		var p SyncPayload
		if json.Unmarshal(msg.Payload, &p) == nil {
			r.state.Song = p.Song
			r.state.Queue = append([]SongInfo(nil), p.Queue...)
			r.state.IsPlaying = p.IsPlaying
			r.state.PositionMs = p.PositionMs
			r.state.UpdatedAt = now
		}
	case TypePlay, TypeNext:
		var p PlayPayload
		if json.Unmarshal(msg.Payload, &p) == nil {
			r.state.Song = &p.Song
			if len(r.state.Queue) == 0 {
				r.state.Queue = []SongInfo{p.Song}
			}
			r.state.IsPlaying = true
			r.state.PositionMs = p.PositionMs
			r.state.UpdatedAt = now
		}
	case TypePause:
		var p PositionPayload
		if json.Unmarshal(msg.Payload, &p) == nil {
			r.state.IsPlaying = false
			r.state.PositionMs = p.PositionMs
			r.state.UpdatedAt = now
		}
	case TypeSeek:
		var p PositionPayload
		if json.Unmarshal(msg.Payload, &p) == nil {
			r.state.PositionMs = p.PositionMs
			r.state.UpdatedAt = now
		}
	}
}

// closeAll déconnecte tous les clients (appelé par Hub.CloseRoom).
func (r *Room) closeAll() {
	msg := encode(Outgoing{Type: TypeHostLeft})

	r.mu.Lock()
	clients := make([]*Client, 0, len(r.clients))
	for c := range r.clients {
		clients = append(clients, c)
	}
	r.mu.Unlock()

	for _, c := range clients {
		select {
		case c.send <- msg:
		default:
		}
		c.conn.Close()
	}
}

func (r *Room) broadcastAll(msg Outgoing) {
	data := encode(msg)
	r.mu.RLock()
	defer r.mu.RUnlock()
	for c := range r.clients {
		select {
		case c.send <- data:
		default:
		}
	}
}

func (r *Room) broadcastExcept(skip *Client, msg Outgoing) {
	data := encode(msg)
	r.mu.RLock()
	defer r.mu.RUnlock()
	for c := range r.clients {
		if c == skip {
			continue
		}
		select {
		case c.send <- data:
		default:
		}
	}
}

// participantListLocked retourne la liste des participants.
// Doit être appelé avec r.mu tenu (au moins en lecture).
func (r *Room) participantListLocked() []ParticipantInfo {
	list := make([]ParticipantInfo, 0, len(r.clients))
	for c := range r.clients {
		list = append(list, r.participantInfo(c))
	}
	return list
}

func (r *Room) participantInfo(c *Client) ParticipantInfo {
	return ParticipantInfo{
		ClientID: c.clientID,
		UserID:   c.userID,
		Name:     c.name,
		IsHost:   c.isHost,
	}
}
