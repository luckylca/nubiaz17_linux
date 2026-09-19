package hub

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/coder/websocket"
)

// Hub fans out snapshot JSON to all connected websocket clients.
type Hub struct {
	mu      sync.Mutex
	clients map[*client]struct{}
}

type client struct {
	conn *websocket.Conn
	send chan []byte
}

func New() *Hub { return &Hub{clients: map[*client]struct{}{}} }

// Broadcast sends msg to all clients; slow clients are dropped.
func (h *Hub) Broadcast(msg []byte) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for c := range h.clients {
		select {
		case c.send <- msg:
		default:
			// client too slow; drop it
			close(c.send)
			delete(h.clients, c)
		}
	}
}

// Count returns the number of connected clients.
func (h *Hub) Count() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.clients)
}

// ServeWS upgrades the connection and pumps messages until close.
func (h *Hub) ServeWS(ctx context.Context, w http.ResponseWriter, r *http.Request) {
	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		// same-origin local UI; compression off (CPU)
		CompressionMode: websocket.CompressionDisabled,
	})
	if err != nil {
		log.Printf("ws accept: %v", err)
		return
	}
	c := &client{conn: conn, send: make(chan []byte, 8)}
	h.mu.Lock()
	h.clients[c] = struct{}{}
	h.mu.Unlock()

	defer func() {
		h.mu.Lock()
		if _, ok := h.clients[c]; ok {
			delete(h.clients, c)
			close(c.send)
		}
		h.mu.Unlock()
		conn.Close(websocket.StatusNormalClosure, "")
	}()

	// reader: keep the connection alive / detect close
	go func() {
		for {
			if _, _, err := conn.Read(ctx); err != nil {
				h.mu.Lock()
				if _, ok := h.clients[c]; ok {
					delete(h.clients, c)
					close(c.send)
				}
				h.mu.Unlock()
				return
			}
		}
	}()

	for msg := range c.send {
		wctx, cancel := context.WithTimeout(ctx, 5*time.Second)
		err := conn.Write(wctx, websocket.MessageText, msg)
		cancel()
		if err != nil {
			return
		}
	}
}

// Marshal helper.
func Marshal(v any) []byte {
	b, err := json.Marshal(v)
	if err != nil {
		return nil
	}
	return b
}
