package handlers

import "app/services"

// ErrorResponse représente un message d'erreur générique.
type ErrorResponse struct {
	Error string `json:"error"`
}

// HealthResponse représente la réponse de /health.
type HealthResponse struct {
	Status string `json:"status"`
	Error  string `json:"error,omitempty"`
}

// SignupRequest représente le payload de création de compte.
type SignupRequest struct {
	Name     string `json:"name"     binding:"required,min=2,max=100"        example:"Alice"`
	Email    string `json:"email"    binding:"required,email"                example:"alice@example.com"`
	Password string `json:"password" binding:"required,min=8,max=128"        example:"myS3cretPass"`
}

// LoginRequest représente le payload de connexion.
type LoginRequest struct {
	Email    string `json:"email"    binding:"required,email"         example:"alice@example.com"`
	Password string `json:"password" binding:"required,min=1,max=128" example:"myS3cretPass"`
}

// RefreshRequest représente le payload de renouvellement de token.
type RefreshRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required" example:"xYzRefreshToken"`
}

// AuthTokensResponse représente la réponse de login/refresh.
type AuthTokensResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	TokenType    string `json:"token_type" example:"Bearer"`
}

// UpdateProfileRequest représente le payload de mise à jour du profil (tous les champs sont optionnels).
type UpdateProfileRequest struct {
	FirstName *string `json:"first_name" binding:"omitempty,min=1,max=100" example:"Alice"`
	LastName  *string `json:"last_name"  binding:"omitempty,min=1,max=100" example:"Dupont"`
	Email     *string `json:"email"      binding:"omitempty,email"         example:"alice@example.com"`
}

// SongRequest représente les métadonnées d'une musique passées par le client.
// Utilisé aussi bien pour liker une musique que pour l'ajouter à une playlist.
type SongRequest struct {
	ExternalID string  `json:"external_id" binding:"required,min=1,max=255" example:"spotify:track:4uLU6hMCjMI75M1A2tKUQC"`
	Title      string  `json:"title"       binding:"required,min=1,max=255" example:"Never Gonna Give You Up"`
	Artist     string  `json:"artist"      binding:"required,min=1,max=255" example:"Rick Astley"`
	Album      *string `json:"album"       binding:"omitempty,max=255"      example:"Whenever You Need Somebody"`
	CoverURL   *string `json:"cover_url"   binding:"omitempty,url"          example:"https://i.scdn.co/image/ab67616d0000b273"`
	DurationMs *int    `json:"duration_ms" binding:"omitempty,min=0"        example:"213573"`
}

// toServiceInput convertit la requête en type d'entrée service.
func (r SongRequest) toServiceInput() services.SongInput {
	return services.SongInput{
		ExternalID: r.ExternalID,
		Title:      r.Title,
		Artist:     r.Artist,
		Album:      r.Album,
		CoverURL:   r.CoverURL,
		DurationMs: r.DurationMs,
	}
}

// SetLikeVisibilityRequest représente le payload pour changer la visibilité d'un like.
// IsPublic est un pointeur pour distinguer false explicite de valeur absente.
type SetLikeVisibilityRequest struct {
	IsPublic *bool `json:"is_public" binding:"required" example:"true"`
}

// CreatePlaylistRequest représente le payload de création d'une playlist.
type CreatePlaylistRequest struct {
	Name        string  `json:"name"        binding:"required,min=1,max=255" example:"Ma playlist du soir"`
	Description *string `json:"description" binding:"omitempty,max=500"      example:"Pour se détendre"`
}

// UpdatePlaylistRequest représente le payload de mise à jour d'une playlist (tous les champs sont optionnels).
type UpdatePlaylistRequest struct {
	Name        *string `json:"name"        binding:"omitempty,min=1,max=255" example:"Ma playlist"`
	Description *string `json:"description" binding:"omitempty,max=500"       example:"Description mise à jour"`
	IsPublic    *bool   `json:"is_public"   binding:"omitempty"               example:"false"`
}

// SendFriendRequestBody représente le payload d'envoi d'une demande d'amitié.
type SendFriendRequestBody struct {
	AddresseeID int `json:"addressee_id" binding:"required,min=1" example:"42"`
}
