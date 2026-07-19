package services

import (
	"database/sql"
	"errors"
	"fmt"

	"app/sanitize"

	"github.com/lib/pq"
	"golang.org/x/crypto/bcrypt"
)

var (
	ErrEmailAlreadyExists = errors.New("email already exists")
	ErrUserNotFound       = errors.New("user not found")
	ErrNoFieldsToUpdate   = errors.New("no fields to update")
)

// User représente la table users.
type User struct {
	ID        int    `json:"id"`
	Name      string `json:"name"`
	Email     string `json:"email"`
	FirstName string `json:"first_name,omitempty"`
	LastName  string `json:"last_name,omitempty"`
}

// UpdateProfileInput contient les champs modifiables du profil (pointeurs = champ optionnel).
type UpdateProfileInput struct {
	FirstName *string
	LastName  *string
	Email     *string
}

// UserService porte la logique métier liée aux utilisateurs.
type UserService struct {
	db *sql.DB
}

func NewUserService(db *sql.DB) *UserService {
	return &UserService{db: db}
}

// Create insère un utilisateur avec mot de passe haché.
// Le nom est normalisé (espaces) et l'email mis en minuscules avant stockage.
func (s *UserService) Create(name, email, password string) (*User, error) {
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("hash password: %w", err)
	}

	var u User
	err = s.db.QueryRow(
		`INSERT INTO users (name, email, password_hash) VALUES ($1, $2, $3) RETURNING id, name, email`,
		sanitize.Name(name), sanitize.Email(email), string(hashedPassword),
	).Scan(&u.ID, &u.Name, &u.Email)
	if err != nil {
		if pqErr, ok := err.(*pq.Error); ok && pqErr.Code == "23505" {
			return nil, ErrEmailAlreadyExists
		}
		return nil, fmt.Errorf("insert user: %w", err)
	}
	return &u, nil
}

// GetByID retourne le profil complet d'un utilisateur.
func (s *UserService) GetByID(id int) (*User, error) {
	var u User
	var firstName, lastName sql.NullString

	err := s.db.QueryRow(
		`SELECT id, name, email, first_name, last_name FROM users WHERE id = $1`,
		id,
	).Scan(&u.ID, &u.Name, &u.Email, &firstName, &lastName)
	if err == sql.ErrNoRows {
		return nil, ErrUserNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("query user: %w", err)
	}

	if firstName.Valid {
		u.FirstName = firstName.String
	}
	if lastName.Valid {
		u.LastName = lastName.String
	}
	return &u, nil
}

// UpdateProfile met à jour les champs fournis. Utilise le queryBuilder pour
// construire la clause SET de façon paramétrée (pas d'injection SQL possible).
func (s *UserService) UpdateProfile(id int, input UpdateProfileInput) (*User, error) {
	qb := newQueryBuilder()

	if input.FirstName != nil {
		qb.add("first_name", sanitize.Name(*input.FirstName))
	}
	if input.LastName != nil {
		qb.add("last_name", sanitize.Name(*input.LastName))
	}
	if input.Email != nil {
		qb.add("email", sanitize.Email(*input.Email))
	}

	if qb.empty() {
		return nil, ErrNoFieldsToUpdate
	}

	setClauses, args, idx := qb.build(id)
	query := fmt.Sprintf(
		`UPDATE users SET %s WHERE id = $%d RETURNING id, name, email, first_name, last_name`,
		setClauses, idx,
	)

	var u User
	var firstName, lastName sql.NullString

	err := s.db.QueryRow(query, args...).Scan(&u.ID, &u.Name, &u.Email, &firstName, &lastName)
	if err == sql.ErrNoRows {
		return nil, ErrUserNotFound
	}
	if err != nil {
		if pqErr, ok := err.(*pq.Error); ok && pqErr.Code == "23505" {
			return nil, ErrEmailAlreadyExists
		}
		return nil, fmt.Errorf("update user: %w", err)
	}

	if firstName.Valid {
		u.FirstName = firstName.String
	}
	if lastName.Valid {
		u.LastName = lastName.String
	}
	return &u, nil
}
