// Package sanitize normalise les entrées utilisateur avant stockage ou traitement.
// Il ne valide pas le format (c'est le rôle des binding tags gin) ; il garantit
// que les données sont propres et cohérentes (casse, espaces superflus).
package sanitize

import "strings"

// Email met l'adresse en minuscules et supprime les espaces en début/fin.
// Garantit que "Alice@EXAMPLE.com " et "alice@example.com" sont identiques en base.
func Email(s string) string {
	return strings.ToLower(strings.TrimSpace(s))
}

// Name supprime les espaces en début/fin et normalise les espaces internes
// (plusieurs espaces consécutifs → un seul). Utile pour les noms, titres, artistes.
func Name(s string) string {
	return strings.Join(strings.Fields(s), " ")
}

// String supprime uniquement les espaces en début et fin de chaîne.
func String(s string) string {
	return strings.TrimSpace(s)
}
