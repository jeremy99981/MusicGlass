package services

import (
	"strings"
	"testing"
	"unicode/utf8"
)

func TestNormalizeSearchQuery(t *testing.T) {
	if got := NormalizeSearchQuery("  Ziak   FENG SHUI  "); got != "Ziak FENG SHUI" {
		t.Fatalf("unexpected normalized query %q", got)
	}
	if got := NormalizeSearchQuery(" \n\t "); got != "" {
		t.Fatalf("expected empty query, got %q", got)
	}
}

func TestNormalizeSearchQueryPreservesUTF8(t *testing.T) {
	query := strings.Repeat("é", 161)
	got := NormalizeSearchQuery(query)
	if utf8.RuneCountInString(got) != 160 || !utf8.ValidString(got) {
		t.Fatalf("expected 160 valid UTF-8 runes, got %d (%q)", utf8.RuneCountInString(got), got)
	}
}
