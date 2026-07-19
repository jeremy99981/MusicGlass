package services

import (
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/lib/pq"
)

var (
	ErrFriendRequestNotFound = errors.New("friend request not found")
	ErrAlreadyFriends        = errors.New("friendship already exists")
	ErrCannotFriendYourself  = errors.New("cannot send friend request to yourself")
)

// Friendship représente une demande d'amitié ou une amitié acceptée.
type Friendship struct {
	ID          int       `json:"id"`
	RequesterID int       `json:"requester_id"`
	AddresseeID int       `json:"addressee_id"`
	Status      string    `json:"status"` // "pending" | "accepted"
	CreatedAt   time.Time `json:"created_at"`
}

// FriendInfo représente les infos publiques d'un ami.
type FriendInfo struct {
	UserID int    `json:"user_id"`
	Name   string `json:"name"`
	Email  string `json:"email"`
}

// FriendService porte la logique métier du système d'amis.
type FriendService struct {
	db *sql.DB
}

func NewFriendService(db *sql.DB) *FriendService {
	return &FriendService{db: db}
}

// SendRequest envoie une demande d'amitié de requesterID vers addresseeID.
func (s *FriendService) SendRequest(requesterID, addresseeID int) (*Friendship, error) {
	if requesterID == addresseeID {
		return nil, ErrCannotFriendYourself
	}

	var f Friendship
	err := s.db.QueryRow(`
		INSERT INTO friendships (requester_id, addressee_id, status)
		VALUES ($1, $2, 'pending')
		RETURNING id, requester_id, addressee_id, status, created_at`,
		requesterID, addresseeID,
	).Scan(&f.ID, &f.RequesterID, &f.AddresseeID, &f.Status, &f.CreatedAt)
	if err != nil {
		if pqErr, ok := err.(*pq.Error); ok && pqErr.Code == "23505" {
			return nil, ErrAlreadyFriends
		}
		return nil, fmt.Errorf("send friend request: %w", err)
	}
	return &f, nil
}

// AcceptRequest accepte une demande en attente reçue par addresseeID.
func (s *FriendService) AcceptRequest(addresseeID, requestID int) (*Friendship, error) {
	var f Friendship
	err := s.db.QueryRow(`
		UPDATE friendships SET status = 'accepted', updated_at = NOW()
		WHERE id = $1 AND addressee_id = $2 AND status = 'pending'
		RETURNING id, requester_id, addressee_id, status, created_at`,
		requestID, addresseeID,
	).Scan(&f.ID, &f.RequesterID, &f.AddresseeID, &f.Status, &f.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, ErrFriendRequestNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("accept friend request: %w", err)
	}
	return &f, nil
}

// DeclineRequest refuse ou annule une demande en attente.
func (s *FriendService) DeclineRequest(addresseeID, requestID int) error {
	res, err := s.db.Exec(`
		DELETE FROM friendships
		WHERE id = $1 AND addressee_id = $2 AND status = 'pending'`,
		requestID, addresseeID,
	)
	if err != nil {
		return fmt.Errorf("decline friend request: %w", err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrFriendRequestNotFound
	}
	return nil
}

// ListPendingRequests liste les demandes reçues en attente pour userID.
func (s *FriendService) ListPendingRequests(userID int) ([]Friendship, error) {
	rows, err := s.db.Query(`
		SELECT id, requester_id, addressee_id, status, created_at
		FROM friendships
		WHERE addressee_id = $1 AND status = 'pending'
		ORDER BY created_at DESC`,
		userID,
	)
	if err != nil {
		return nil, fmt.Errorf("list pending requests: %w", err)
	}
	defer rows.Close()

	requests := make([]Friendship, 0)
	for rows.Next() {
		var f Friendship
		if err := rows.Scan(&f.ID, &f.RequesterID, &f.AddresseeID, &f.Status, &f.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan friendship: %w", err)
		}
		requests = append(requests, f)
	}
	return requests, rows.Err()
}

// ListFriends liste les amis acceptés de userID.
func (s *FriendService) ListFriends(userID int) ([]FriendInfo, error) {
	rows, err := s.db.Query(`
		SELECT u.id, u.name, u.email
		FROM friendships f
		JOIN users u ON u.id = CASE
			WHEN f.requester_id = $1 THEN f.addressee_id
			ELSE f.requester_id
		END
		WHERE (f.requester_id = $1 OR f.addressee_id = $1)
		  AND f.status = 'accepted'
		ORDER BY u.name ASC`,
		userID,
	)
	if err != nil {
		return nil, fmt.Errorf("list friends: %w", err)
	}
	defer rows.Close()

	friends := make([]FriendInfo, 0)
	for rows.Next() {
		var fi FriendInfo
		if err := rows.Scan(&fi.UserID, &fi.Name, &fi.Email); err != nil {
			return nil, fmt.Errorf("scan friend: %w", err)
		}
		friends = append(friends, fi)
	}
	return friends, rows.Err()
}

// RemoveFriend supprime une amitié acceptée entre userID et friendID.
func (s *FriendService) RemoveFriend(userID, friendID int) error {
	res, err := s.db.Exec(`
		DELETE FROM friendships
		WHERE status = 'accepted'
		  AND ((requester_id = $1 AND addressee_id = $2)
		    OR (requester_id = $2 AND addressee_id = $1))`,
		userID, friendID,
	)
	if err != nil {
		return fmt.Errorf("remove friend: %w", err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrFriendRequestNotFound
	}
	return nil
}
