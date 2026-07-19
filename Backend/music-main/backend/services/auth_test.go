package services

import (
	"os"
	"testing"
)

func TestGenerateAndParseAccessToken(t *testing.T) {
	t.Setenv("JWT_SECRET", "test-secret")
	t.Setenv("ACCESS_TOKEN_TTL_MINUTES", "60")

	token, err := GenerateAccessToken(42)
	if err != nil {
		t.Fatalf("GenerateAccessToken() error = %v", err)
	}

	claims, err := ParseAccessToken(token)
	if err != nil {
		t.Fatalf("ParseAccessToken() error = %v", err)
	}

	if claims.UserID != 42 {
		t.Fatalf("expected user id 42, got %d", claims.UserID)
	}

	if claims.ExpiresAt == nil {
		t.Fatal("expected non-nil expiration")
	}
}

func TestParseAccessTokenInvalid(t *testing.T) {
	t.Setenv("JWT_SECRET", "test-secret")

	_, err := ParseAccessToken("invalid.token.value")
	if err == nil {
		t.Fatal("expected parse error for invalid token")
	}
}

func TestParseAccessTokenWrongSecret(t *testing.T) {
	t.Setenv("JWT_SECRET", "first-secret")
	token, err := GenerateAccessToken(7)
	if err != nil {
		t.Fatalf("GenerateAccessToken() error = %v", err)
	}

	if err := os.Setenv("JWT_SECRET", "second-secret"); err != nil {
		t.Fatalf("setenv error = %v", err)
	}

	_, err = ParseAccessToken(token)
	if err == nil {
		t.Fatal("expected parse failure with wrong secret")
	}
}
