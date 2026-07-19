package services

import (
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"strconv"
	"time"

	"app/sanitize"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

var (
	ErrInvalidCredentials  = errors.New("invalid credentials")
	ErrInvalidRefreshToken = errors.New("invalid refresh token")
)

type AccessClaims struct {
	UserID int `json:"user_id"`
	jwt.RegisteredClaims
}

type AuthService struct {
	db *sql.DB
}

func NewAuthService(db *sql.DB) *AuthService {
	return &AuthService{db: db}
}

func jwtSecret() []byte {
	secret := os.Getenv("JWT_SECRET")
	if secret == "" {
		secret = "dev-secret-change-me"
	}
	return []byte(secret)
}

func accessTokenTTL() time.Duration {
	minutes := 15
	if raw := os.Getenv("ACCESS_TOKEN_TTL_MINUTES"); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil && parsed > 0 {
			minutes = parsed
		}
	}
	return time.Duration(minutes) * time.Minute
}

func refreshTokenTTL() time.Duration {
	hours := 24 * 7
	if raw := os.Getenv("REFRESH_TOKEN_TTL_HOURS"); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil && parsed > 0 {
			hours = parsed
		}
	}
	return time.Duration(hours) * time.Hour
}

func GenerateAccessToken(userID int) (string, error) {
	now := time.Now()
	claims := AccessClaims{
		UserID: userID,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(now.Add(accessTokenTTL())),
			IssuedAt:  jwt.NewNumericDate(now),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString(jwtSecret())
	if err != nil {
		return "", fmt.Errorf("sign access token: %w", err)
	}
	return signed, nil
}

func ParseAccessToken(tokenString string) (*AccessClaims, error) {
	claims := &AccessClaims{}
	token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method")
		}
		return jwtSecret(), nil
	})
	if err != nil || !token.Valid {
		return nil, ErrInvalidCredentials
	}
	return claims, nil
}

func (s *AuthService) Login(email, password string) (string, string, error) {
	email = sanitize.Email(email) // garantit la cohérence avec la normalisation à l'inscription

	var (
		id           int
		passwordHash string
	)

	err := s.db.QueryRow(`SELECT id, password_hash FROM users WHERE email = $1`, email).Scan(&id, &passwordHash)
	if err == sql.ErrNoRows {
		return "", "", ErrInvalidCredentials
	}
	if err != nil {
		return "", "", fmt.Errorf("query user credentials: %w", err)
	}

	if err := bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(password)); err != nil {
		return "", "", ErrInvalidCredentials
	}

	accessToken, err := GenerateAccessToken(id)
	if err != nil {
		return "", "", err
	}

	refreshToken, err := s.createRefreshToken(id)
	if err != nil {
		return "", "", err
	}

	return accessToken, refreshToken, nil
}

func (s *AuthService) Refresh(refreshToken string) (string, string, error) {
	hash := hashRefreshToken(refreshToken)

	var (
		storedID  int
		userID    int
		expiresAt time.Time
		revoked   bool
	)

	err := s.db.QueryRow(
		`SELECT id, user_id, expires_at, revoked FROM refresh_tokens WHERE token_hash = $1`,
		hash,
	).Scan(&storedID, &userID, &expiresAt, &revoked)
	if err == sql.ErrNoRows {
		return "", "", ErrInvalidRefreshToken
	}
	if err != nil {
		return "", "", fmt.Errorf("query refresh token: %w", err)
	}

	if revoked || time.Now().After(expiresAt) {
		return "", "", ErrInvalidRefreshToken
	}

	tx, err := s.db.Begin()
	if err != nil {
		return "", "", fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	if _, err := tx.Exec(`UPDATE refresh_tokens SET revoked = TRUE WHERE id = $1`, storedID); err != nil {
		return "", "", fmt.Errorf("revoke refresh token: %w", err)
	}

	newRefreshToken, newRefreshHash, newExpiresAt, err := buildRefreshToken()
	if err != nil {
		return "", "", err
	}

	if _, err := tx.Exec(
		`INSERT INTO refresh_tokens (token_hash, user_id, expires_at, revoked) VALUES ($1, $2, $3, FALSE)`,
		newRefreshHash,
		userID,
		newExpiresAt,
	); err != nil {
		return "", "", fmt.Errorf("insert rotated refresh token: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return "", "", fmt.Errorf("commit tx: %w", err)
	}

	newAccessToken, err := GenerateAccessToken(userID)
	if err != nil {
		return "", "", err
	}

	return newAccessToken, newRefreshToken, nil
}

func (s *AuthService) createRefreshToken(userID int) (string, error) {
	refreshToken, hash, expiresAt, err := buildRefreshToken()
	if err != nil {
		return "", err
	}

	_, err = s.db.Exec(
		`INSERT INTO refresh_tokens (token_hash, user_id, expires_at, revoked) VALUES ($1, $2, $3, FALSE)`,
		hash,
		userID,
		expiresAt,
	)
	if err != nil {
		return "", fmt.Errorf("insert refresh token: %w", err)
	}

	return refreshToken, nil
}

func buildRefreshToken() (string, string, time.Time, error) {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", "", time.Time{}, fmt.Errorf("generate refresh token: %w", err)
	}

	token := base64.RawURLEncoding.EncodeToString(bytes)
	hash := hashRefreshToken(token)
	expiresAt := time.Now().Add(refreshTokenTTL())

	return token, hash, expiresAt, nil
}

func hashRefreshToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}
