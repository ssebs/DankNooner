package main

import (
	"encoding/json"
	"log"
	"math"
	"math/rand"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

const (
	msgJoin           = 0
	msgID             = 1
	msgPeerConnect    = 2
	msgPeerDisconnect = 3
	msgOffer          = 4
	msgAnswer         = 5
	msgCandidate      = 6
	msgSeal           = 7

	// TARGET_PEER_SERVER in Godot's MultiplayerPeer — means "send to host"
	targetServer = 1

	sigTimeout = 10 * time.Second
	sealDelay  = 10 * time.Second
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type sigMsg struct {
	Type int    `json:"type"`
	ID   int    `json:"id"`
	Data string `json:"data"`
}

// Peer represents a connected WebSocket client.
type Peer struct {
	id       int
	conn     *websocket.Conn
	lobby    string
	mu       sync.Mutex // guards writes
	joinedAt time.Time
}

func (p *Peer) send(msgType, id int, data string) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.conn.WriteJSON(sigMsg{Type: msgType, ID: id, Data: data})
}

// Lobby tracks the host and all connected peers for one game session.
type Lobby struct {
	host   int
	peers  map[int]*Peer
	sealed bool
}

func newLobby(hostID int) *Lobby {
	return &Lobby{host: hostID, peers: make(map[int]*Peer)}
}

// join sends the joining peer their ID, notifies existing peers, and adds
// the peer to the lobby. In client-server mode only the host is visible to
// newly joining clients (and vice-versa).
func (l *Lobby) join(p *Peer) bool {
	if l.sealed {
		return false
	}
	assignedID := p.id
	if p.id == l.host {
		assignedID = targetServer // host always appears as ID 1
	}
	p.send(msgID, assignedID, "")

	for _, existing := range l.peers {
		if existing.id != l.host {
			continue // only host visible in client-server mode
		}
		existing.send(msgPeerConnect, p.id, "")
		existingID := existing.id
		if existingID == l.host {
			existingID = targetServer
		}
		p.send(msgPeerConnect, existingID, "")
	}
	l.peers[p.id] = p
	return true
}

// leave removes a peer. Returns true if the lobby should be destroyed
// (host left).
func (l *Lobby) leave(p *Peer) bool {
	delete(l.peers, p.id)
	closeAll := p.id == l.host
	if l.sealed {
		return closeAll
	}
	for _, other := range l.peers {
		if closeAll {
			other.conn.Close()
		} else {
			other.send(msgPeerDisconnect, p.id, "")
		}
	}
	return closeAll
}

// seal closes the lobby for new connections and broadcasts SEAL to all peers.
func (l *Lobby) seal(peerID int) bool {
	if l.host != peerID {
		return false
	}
	l.sealed = true
	for _, p := range l.peers {
		p.send(msgSeal, 0, "")
	}
	l.peers = make(map[int]*Peer) // signaling no longer needed
	return true
}

// Hub manages all active lobbies.
type Hub struct {
	mu      sync.Mutex
	lobbies map[string]*Lobby
	rng     *rand.Rand
}

func newHub() *Hub {
	return &Hub{
		lobbies: make(map[string]*Lobby),
		rng:     rand.New(rand.NewSource(time.Now().UnixNano())),
	}
}

const alfnum = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"

func (h *Hub) randomCode(n int) string {
	b := make([]byte, n)
	for i := range b {
		b[i] = alfnum[h.rng.Intn(len(alfnum))]
	}
	return string(b)
}

// joinLobby creates a new lobby (code="") or joins an existing one.
func (h *Hub) joinLobby(p *Peer, code string) (string, bool) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if code == "" {
		for {
			code = h.randomCode(32)
			if _, exists := h.lobbies[code]; !exists {
				break
			}
		}
		h.lobbies[code] = newLobby(p.id)
	} else {
		if _, exists := h.lobbies[code]; !exists {
			return "", false
		}
	}
	lobby := h.lobbies[code]
	if !lobby.join(p) {
		return "", false
	}
	p.lobby = code
	log.Printf("peer %d joined lobby %s", p.id, code)
	return code, true
}

func (h *Hub) removePeer(p *Peer) {
	if p.lobby == "" {
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	lobby, ok := h.lobbies[p.lobby]
	if !ok {
		return
	}
	if lobby.leave(p) {
		delete(h.lobbies, p.lobby)
		log.Printf("lobby %s closed (host left)", p.lobby)
	}
}

func (h *Hub) relay(p *Peer, msg sigMsg) bool {
	h.mu.Lock()
	defer h.mu.Unlock()

	lobby, ok := h.lobbies[p.lobby]
	if !ok {
		return false
	}

	destID := msg.ID
	if destID == targetServer {
		destID = lobby.host
	}

	dest, ok := lobby.peers[destID]
	if !ok || dest.lobby != p.lobby {
		return false
	}

	sourceID := p.id
	if p.id == lobby.host {
		sourceID = targetServer
	}
	return dest.send(msg.Type, sourceID, msg.Data) == nil
}

func (h *Hub) sealLobby(p *Peer) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	lobby, ok := h.lobbies[p.lobby]
	if !ok {
		return false
	}
	ok = lobby.seal(p.id)
	if ok {
		// Remove the sealed lobby after the delay in a background goroutine.
		code := p.lobby
		go func() {
			time.Sleep(sealDelay)
			h.mu.Lock()
			delete(h.lobbies, code)
			h.mu.Unlock()
			log.Printf("lobby %s cleaned up after seal", code)
		}()
	}
	return ok
}

// ServeWS upgrades the HTTP connection and handles one peer for its lifetime.
func (h *Hub) ServeWS(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("upgrade error: %v", err)
		return
	}

	p := &Peer{
		id:       int(rand.Int31n(math.MaxInt32-1)) + 2, // Godot peer IDs: [1, 2^31-1]; 1 is reserved for host
		conn:     conn,
		joinedAt: time.Now(),
	}
	log.Printf("peer %d connected from %s", p.id, r.RemoteAddr)

	defer func() {
		h.removePeer(p)
		conn.Close()
		log.Printf("peer %d disconnected", p.id)
	}()

	// Enforce join timeout: peer must join a lobby within sigTimeout.
	conn.SetReadDeadline(time.Now().Add(sigTimeout))

	for {
		_, raw, err := conn.ReadMessage()
		if err != nil {
			return
		}

		var msg sigMsg
		if err := json.Unmarshal(raw, &msg); err != nil {
			log.Printf("peer %d: bad JSON: %v", p.id, err)
			return
		}

		switch msg.Type {
		case msgJoin:
			if p.lobby != "" {
				return // already in a lobby
			}
			code, ok := h.joinLobby(p, msg.Data)
			if !ok {
				log.Printf("peer %d: join failed for code %q", p.id, msg.Data)
				return
			}
			p.send(msgJoin, 0, code)
			// Joined — clear the deadline, stay connected as long as needed.
			conn.SetReadDeadline(time.Time{})

		case msgSeal:
			if p.lobby == "" {
				return
			}
			h.sealLobby(p)

		case msgOffer, msgAnswer, msgCandidate:
			if p.lobby == "" {
				return
			}
			h.relay(p, msg)

		default:
			log.Printf("peer %d: unknown message type %d", p.id, msg.Type)
			return
		}
	}
}
