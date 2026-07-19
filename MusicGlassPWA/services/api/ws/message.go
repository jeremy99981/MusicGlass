package ws

import (
	"encoding/json"
	"time"
)

// Type désigne le rôle d'un message WebSocket.
type Type string

const (
	TypePlay     Type = "play"      // hôte → tous : lecture lancée
	TypePause    Type = "pause"     // hôte → tous : pause
	TypeSeek     Type = "seek"      // hôte → tous : déplacement de tête
	TypeNext     Type = "next"      // hôte → tous : changement de musique
	TypeSync     Type = "sync"      // hôte → tous : état complet du lecteur et de la file
	TypeState    Type = "state"     // serveur → entrant : état courant complet
	TypeJoined   Type = "joined"    // serveur → tous : quelqu'un a rejoint
	TypeLeft     Type = "left"      // serveur → tous : quelqu'un est parti
	TypeHostLeft Type = "host_left" // serveur → tous : l'hôte s'est déconnecté
	TypeError    Type = "error"     // serveur → client : message d'erreur
)

// Incoming est un message envoyé par un client au serveur.
type Incoming struct {
	Type    Type            `json:"type"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

// Outgoing est un message envoyé par le serveur à un ou plusieurs clients.
type Outgoing struct {
	Type           Type        `json:"type"`
	SenderID       int         `json:"sender_id,omitempty"`
	SenderClientID string      `json:"sender_client_id,omitempty"`
	Payload        interface{} `json:"payload,omitempty"`
}

// SongInfo identifie une musique dans le lecteur partagé.
type SongInfo struct {
	ExternalID string   `json:"external_id"`
	Title      string   `json:"title"`
	Artist     string   `json:"artist"`
	CoverURL   string   `json:"cover_url,omitempty"`
	CoverURLs  []string `json:"cover_urls,omitempty"`
	DurationMs int64    `json:"duration_ms,omitempty"`
}

// PlayPayload payload des messages play et next.
type PlayPayload struct {
	Song       SongInfo `json:"song"`
	PositionMs int64    `json:"position_ms"`
}

// PositionPayload payload des messages pause et seek.
type PositionPayload struct {
	PositionMs int64 `json:"position_ms"`
}

// SyncPayload transporte toute la source de vérité du lecteur de l'hôte.
type SyncPayload struct {
	Song       *SongInfo  `json:"song,omitempty"`
	Queue      []SongInfo `json:"queue"`
	IsPlaying  bool       `json:"is_playing"`
	PositionMs int64      `json:"position_ms"`
}

// PlaybackState état courant du lecteur partagé, stocké dans la Room.
// UpdatedAt permet aux clients de recalculer la position courante si IsPlaying=true.
type PlaybackState struct {
	Song       *SongInfo  `json:"song,omitempty"`
	Queue      []SongInfo `json:"queue"`
	IsPlaying  bool       `json:"is_playing"`
	PositionMs int64      `json:"position_ms"`
	UpdatedAt  time.Time  `json:"updated_at"`
}

// StatePayload envoyé à un client qui rejoint la session.
type StatePayload struct {
	PlaybackState
	Participants []ParticipantInfo `json:"participants"`
}

// ParticipantInfo infos publiques d'un participant.
type ParticipantInfo struct {
	ClientID string `json:"client_id"`
	UserID   int    `json:"user_id"`
	Name     string `json:"name"`
	IsHost   bool   `json:"is_host"`
}

// encode sérialise un Outgoing en JSON ; erreur ignorée (types fixes).
func encode(msg Outgoing) []byte {
	b, _ := json.Marshal(msg)
	return b
}
