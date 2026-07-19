package ws

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

// ── Helpers ───────────────────────────────────────────────────────────────────

// newTestServer lance un serveur HTTP de test qui upgrade toute connexion en WS
// et joint le client à la room identifiée par le paramètre d'URL.
func newTestServer(t *testing.T, hub *Hub, code string, userID int, name string, hostID int) (*websocket.Conn, func()) {
	return newTestServerWithRole(t, hub, code, userID, name, hostID, userID == hostID)
}

func newTestServerWithRole(t *testing.T, hub *Hub, code string, userID int, name string, hostID int, isHost bool) (*websocket.Conn, func()) {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		up := websocket.Upgrader{CheckOrigin: func(*http.Request) bool { return true }}
		conn, err := up.Upgrade(w, r, nil)
		if err != nil {
			t.Errorf("upgrade: %v", err)
			return
		}
		client := NewClient(hub, userID, name, name+"-client", isHost, conn)
		hub.Join(code, client, hostID)
	}))

	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http")
	conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}

	return conn, func() {
		conn.Close()
		srv.Close()
	}
}

// readMsg lit le prochain message JSON d'une connexion WS avec un timeout.
func readMsg(t *testing.T, conn *websocket.Conn) Outgoing {
	t.Helper()
	conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	_, data, err := conn.ReadMessage()
	if err != nil {
		t.Fatalf("readMsg: %v", err)
	}
	var msg Outgoing
	if err := json.Unmarshal(data, &msg); err != nil {
		t.Fatalf("unmarshal: %v — raw: %s", err, data)
	}
	return msg
}

// sendMsg envoie un message JSON sur une connexion WS.
func sendMsg(t *testing.T, conn *websocket.Conn, msg Incoming) {
	t.Helper()
	data, _ := json.Marshal(msg)
	if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
		t.Fatalf("sendMsg: %v", err)
	}
}

// ── Tests Hub ─────────────────────────────────────────────────────────────────

func TestNewHub_Empty(t *testing.T) {
	hub := NewHub()
	if hub.RoomExists("ANYCODE") {
		t.Error("hub should be empty initially")
	}
}

func TestHub_RoomCreatedOnJoin(t *testing.T) {
	hub := NewHub()
	conn, cleanup := newTestServer(t, hub, "ROOM01", 1, "Alice", 1)
	defer cleanup()

	// Lire le message d'état initial (join crée la room).
	msg := readMsg(t, conn)
	if msg.Type != TypeState {
		t.Errorf("expected state, got %s", msg.Type)
	}

	if !hub.RoomExists("ROOM01") {
		t.Error("room should exist after join")
	}
}

func TestHub_StateContainsParticipant(t *testing.T) {
	hub := NewHub()
	conn, cleanup := newTestServer(t, hub, "ROOM02", 1, "Alice", 1)
	defer cleanup()

	msg := readMsg(t, conn)
	if msg.Type != TypeState {
		t.Fatalf("expected state, got %s", msg.Type)
	}

	var payload StatePayload
	b, _ := json.Marshal(msg.Payload)
	json.Unmarshal(b, &payload)

	if len(payload.Participants) != 1 {
		t.Errorf("expected 1 participant, got %d", len(payload.Participants))
	}
	if payload.Participants[0].UserID != 1 {
		t.Errorf("expected user_id=1, got %d", payload.Participants[0].UserID)
	}
}

func TestHub_JoinedBroadcastToOthers(t *testing.T) {
	hub := NewHub()

	conn1, c1 := newTestServer(t, hub, "ROOM03", 1, "Alice", 1)
	defer c1()
	readMsg(t, conn1) // state initial de Alice

	conn2, c2 := newTestServer(t, hub, "ROOM03", 2, "Bob", 1)
	defer c2()
	readMsg(t, conn2) // state initial de Bob

	// Alice doit avoir reçu un message "joined" pour Bob.
	msg := readMsg(t, conn1)
	if msg.Type != TypeJoined {
		t.Errorf("expected joined, got %s", msg.Type)
	}
}

func TestHub_HostOnlyControl(t *testing.T) {
	hub := NewHub()

	// Alice (user 1) est l'hôte.
	conn1, c1 := newTestServer(t, hub, "ROOM04", 1, "Alice", 1)
	defer c1()
	readMsg(t, conn1) // state

	// Bob (user 2) n'est pas l'hôte.
	conn2, c2 := newTestServer(t, hub, "ROOM04", 2, "Bob", 1)
	defer c2()
	readMsg(t, conn2) // state
	readMsg(t, conn1) // joined (Bob)

	// Bob essaie d'envoyer une commande play → doit recevoir une erreur.
	sendMsg(t, conn2, Incoming{
		Type:    TypePlay,
		Payload: json.RawMessage(`{"song":{"external_id":"yt:x","title":"T","artist":"A"},"position_ms":0}`),
	})

	msg := readMsg(t, conn2)
	if msg.Type != TypeError {
		t.Errorf("expected error, got %s", msg.Type)
	}
}

func TestHub_SameAccountGuestIsNotHost(t *testing.T) {
	hub := NewHub()
	host, closeHost := newTestServerWithRole(t, hub, "SAMEUSER", 1, "Host", 1, true)
	defer closeHost()
	readMsg(t, host)

	guest, closeGuest := newTestServerWithRole(t, hub, "SAMEUSER", 1, "Guest", 1, false)
	defer closeGuest()
	state := readMsg(t, guest)
	readMsg(t, host)

	var payload StatePayload
	b, _ := json.Marshal(state.Payload)
	if err := json.Unmarshal(b, &payload); err != nil {
		t.Fatalf("unmarshal state: %v", err)
	}
	if len(payload.Participants) != 2 {
		t.Fatalf("expected 2 device participants, got %d", len(payload.Participants))
	}
	if payload.Participants[0].ClientID == payload.Participants[1].ClientID {
		t.Fatal("participants should have distinct client ids")
	}

	sendMsg(t, host, Incoming{
		Type: TypeSync,
		Payload: json.RawMessage(`{
			"song":{"external_id":"current","title":"Current","artist":"Artist"},
			"queue":[{"external_id":"current","title":"Current","artist":"Artist"}],
			"is_playing":true,
			"position_ms":12000
		}`),
	})
	if msg := readMsg(t, guest); msg.Type != TypeSync || msg.SenderClientID != "Host-client" {
		t.Fatalf("guest should receive host sync with client identity, got %+v", msg)
	}
	readMsg(t, host)

	sendMsg(t, guest, Incoming{
		Type:    TypePlay,
		Payload: json.RawMessage(`{"song":{"external_id":"x","title":"T","artist":"A"},"position_ms":0}`),
	})
	if msg := readMsg(t, guest); msg.Type != TypeError {
		t.Fatalf("same-account guest should not control playback, got %s", msg.Type)
	}

	guest.Close()
	if msg := readMsg(t, host); msg.Type != TypeLeft {
		t.Fatalf("guest disconnect should emit left, got %s", msg.Type)
	}
}

func TestHub_HostBroadcastsPlay(t *testing.T) {
	hub := NewHub()

	conn1, c1 := newTestServer(t, hub, "ROOM05", 1, "Alice", 1)
	defer c1()
	readMsg(t, conn1) // state

	conn2, c2 := newTestServer(t, hub, "ROOM05", 2, "Bob", 1)
	defer c2()
	readMsg(t, conn2) // state
	readMsg(t, conn1) // joined

	// Alice (hôte) envoie play.
	sendMsg(t, conn1, Incoming{
		Type:    TypePlay,
		Payload: json.RawMessage(`{"song":{"external_id":"yt:abc","title":"Song","artist":"Artist"},"position_ms":0}`),
	})

	// Les deux doivent recevoir le play.
	for _, conn := range []*websocket.Conn{conn1, conn2} {
		msg := readMsg(t, conn)
		if msg.Type != TypePlay {
			t.Errorf("expected play, got %s", msg.Type)
		}
		if msg.SenderID != 1 {
			t.Errorf("expected sender_id=1, got %d", msg.SenderID)
		}
	}
}

func TestHub_StateUpdatedAfterPlay(t *testing.T) {
	hub := NewHub()

	conn1, c1 := newTestServer(t, hub, "ROOM06", 1, "Alice", 1)
	defer c1()
	readMsg(t, conn1)

	sendMsg(t, conn1, Incoming{
		Type:    TypePlay,
		Payload: json.RawMessage(`{"song":{"external_id":"yt:xyz","title":"Track","artist":"DJ"},"position_ms":5000}`),
	})
	readMsg(t, conn1) // play broadcast

	// Un troisième utilisateur rejoint et doit recevoir l'état mis à jour.
	conn3, c3 := newTestServer(t, hub, "ROOM06", 3, "Charlie", 1)
	defer c3()

	msg := readMsg(t, conn3)
	if msg.Type != TypeState {
		t.Fatalf("expected state, got %s", msg.Type)
	}

	var payload StatePayload
	b, _ := json.Marshal(msg.Payload)
	json.Unmarshal(b, &payload)

	if !payload.IsPlaying {
		t.Error("state should show is_playing=true")
	}
	if payload.Song == nil || payload.Song.ExternalID != "yt:xyz" {
		t.Errorf("unexpected song in state: %+v", payload.Song)
	}
}

func TestHub_SyncCarriesQueueAndPlaybackState(t *testing.T) {
	hub := NewHub()
	host, closeHost := newTestServer(t, hub, "ROOMSYNC", 1, "Alice", 1)
	defer closeHost()
	readMsg(t, host)

	sendMsg(t, host, Incoming{
		Type: TypeSync,
		Payload: json.RawMessage(`{
			"song":{"external_id":"current","title":"Current","artist":"Artist","cover_url":"https://example.com/cover.jpg","duration_ms":180000},
			"queue":[
				{"external_id":"current","title":"Current","artist":"Artist","duration_ms":180000},
				{"external_id":"next","title":"Next","artist":"Artist","duration_ms":200000}
			],
			"is_playing":true,
			"position_ms":42000
		}`),
	})
	readMsg(t, host)

	guest, closeGuest := newTestServer(t, hub, "ROOMSYNC", 2, "Bob", 1)
	defer closeGuest()
	msg := readMsg(t, guest)

	var payload StatePayload
	b, _ := json.Marshal(msg.Payload)
	if err := json.Unmarshal(b, &payload); err != nil {
		t.Fatalf("unmarshal state: %v", err)
	}
	if payload.Song == nil || payload.Song.ExternalID != "current" {
		t.Fatalf("unexpected song: %+v", payload.Song)
	}
	if len(payload.Queue) != 2 || payload.Queue[1].ExternalID != "next" {
		t.Fatalf("unexpected queue: %+v", payload.Queue)
	}
	if !payload.IsPlaying || payload.PositionMs != 42000 {
		t.Fatalf("unexpected playback state: playing=%v position=%d", payload.IsPlaying, payload.PositionMs)
	}
}

func TestHub_LargePlaybackSnapshotIsAccepted(t *testing.T) {
	hub := NewHub()
	host, closeHost := newTestServer(t, hub, "LARGEQUEUE", 1, "Host", 1)
	defer closeHost()
	readMsg(t, host)

	queue := make([]SongInfo, 600)
	for i := range queue {
		queue[i] = SongInfo{
			ExternalID: fmt.Sprintf("youtube:track-%d", i),
			Title:      fmt.Sprintf("Queued track number %d with a deliberately long title", i),
			Artist:     "Shared session test artist",
			CoverURL:   fmt.Sprintf("https://example.com/artwork/%d.jpg", i),
			CoverURLs: []string{
				fmt.Sprintf("https://example.com/artwork/%d.jpg", i),
				fmt.Sprintf("https://example.com/artwork/%d-fallback.jpg", i),
			},
		}
	}
	payload, err := json.Marshal(SyncPayload{
		Song:       &queue[0],
		Queue:      queue,
		IsPlaying:  true,
		PositionMs: 42000,
	})
	if err != nil {
		t.Fatalf("marshal large snapshot: %v", err)
	}
	if len(payload) <= 4096 {
		t.Fatalf("test snapshot must exceed the previous 4 KiB limit, got %d bytes", len(payload))
	}

	sendMsg(t, host, Incoming{Type: TypeSync, Payload: payload})
	if msg := readMsg(t, host); msg.Type != TypeSync {
		t.Fatalf("expected large sync broadcast, got %s", msg.Type)
	}

	guest, closeGuest := newTestServer(t, hub, "LARGEQUEUE", 2, "Guest", 1)
	defer closeGuest()
	state := readMsg(t, guest)
	if state.Type != TypeState {
		t.Fatalf("expected state for guest, got %s", state.Type)
	}

	var statePayload StatePayload
	b, _ := json.Marshal(state.Payload)
	if err := json.Unmarshal(b, &statePayload); err != nil {
		t.Fatalf("unmarshal state: %v", err)
	}
	if len(statePayload.Queue) != len(queue) {
		t.Fatalf("expected %d queued tracks, got %d", len(queue), len(statePayload.Queue))
	}
	if len(statePayload.Queue[0].CoverURLs) != 2 {
		t.Fatalf("expected artwork candidates to survive state sync, got %+v", statePayload.Queue[0].CoverURLs)
	}
}

func TestHub_LeftBroadcastOnDisconnect(t *testing.T) {
	hub := NewHub()

	conn1, c1 := newTestServer(t, hub, "ROOM07", 1, "Alice", 1)
	defer c1()
	readMsg(t, conn1)

	conn2, c2 := newTestServer(t, hub, "ROOM07", 2, "Bob", 1)
	defer c2()
	readMsg(t, conn2) // state
	readMsg(t, conn1) // joined

	// Bob se déconnecte.
	conn2.Close()

	// Alice doit recevoir un message "left".
	conn1.SetReadDeadline(time.Now().Add(3 * time.Second))
	msg := readMsg(t, conn1)
	if msg.Type != TypeLeft {
		t.Errorf("expected left, got %s", msg.Type)
	}
}

func TestHub_RoomRemovedWhenEmpty(t *testing.T) {
	hub := NewHub()

	conn, cleanup := newTestServer(t, hub, "ROOM08", 1, "Alice", 1)
	readMsg(t, conn)

	// Déconnecter le seul participant.
	conn.Close()
	cleanup()

	// Laisser les goroutines se terminer.
	time.Sleep(100 * time.Millisecond)

	if hub.RoomExists("ROOM08") {
		t.Error("room should be removed when empty")
	}
}

func TestHub_CloseRoom(t *testing.T) {
	hub := NewHub()

	conn, cleanup := newTestServer(t, hub, "ROOM09", 1, "Alice", 1)
	defer cleanup()
	readMsg(t, conn)

	hub.CloseRoom("ROOM09")

	// Alice doit recevoir host_left.
	conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	_, data, err := conn.ReadMessage()
	if err == nil {
		var msg Outgoing
		json.Unmarshal(data, &msg)
		if msg.Type != TypeHostLeft {
			t.Errorf("expected host_left, got %s", msg.Type)
		}
	}
	// La room ne doit plus exister.
	if hub.RoomExists("ROOM09") {
		t.Error("room should not exist after CloseRoom")
	}
}

func TestHub_UnknownMessageType(t *testing.T) {
	hub := NewHub()
	conn, cleanup := newTestServer(t, hub, "ROOM10", 1, "Alice", 1)
	defer cleanup()
	readMsg(t, conn)

	sendMsg(t, conn, Incoming{Type: "unknown_type"})

	msg := readMsg(t, conn)
	if msg.Type != TypeError {
		t.Errorf("expected error for unknown type, got %s", msg.Type)
	}
}

func TestHub_InvalidJSON(t *testing.T) {
	hub := NewHub()
	conn, cleanup := newTestServer(t, hub, "ROOM11", 1, "Alice", 1)
	defer cleanup()
	readMsg(t, conn)

	conn.WriteMessage(websocket.TextMessage, []byte("not json {{{{"))

	msg := readMsg(t, conn)
	if msg.Type != TypeError {
		t.Errorf("expected error for invalid JSON, got %s", msg.Type)
	}
}
