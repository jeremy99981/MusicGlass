package services

import (
	"fmt"
	"strings"
)

// queryBuilder construit des clauses SET paramétrées pour les requêtes UPDATE dynamiques.
//
// Principe de sécurité :
//   - Les noms de colonnes proviennent UNIQUEMENT du code source (jamais de l'entrée utilisateur).
//   - Les valeurs sont TOUJOURS transmises via des paramètres $N, jamais interpolées.
//   → Aucun risque d'injection SQL possible par construction.
type queryBuilder struct {
	clauses    []string
	args       []interface{}
	nextIdx    int
	userFields int // nombre de champs fournis par l'utilisateur (via add)
}

func newQueryBuilder() *queryBuilder {
	return &queryBuilder{nextIdx: 1}
}

// add ajoute "column = $N" avec la valeur utilisateur correspondante.
// Le nom de colonne est une constante du code, jamais une entrée externe.
func (b *queryBuilder) add(column string, value interface{}) *queryBuilder {
	b.clauses = append(b.clauses, fmt.Sprintf("%s = $%d", column, b.nextIdx))
	b.args = append(b.args, value)
	b.nextIdx++
	b.userFields++
	return b
}

// addLiteral ajoute une expression SQL constante sans paramètre (ex: "updated_at = NOW()").
// Ne compte pas comme champ utilisateur pour le test empty().
func (b *queryBuilder) addLiteral(expr string) *queryBuilder {
	b.clauses = append(b.clauses, expr)
	return b
}

// empty retourne true si aucun champ utilisateur n'a été ajouté via add().
func (b *queryBuilder) empty() bool {
	return b.userFields == 0
}

// build retourne la clause SET complète, les arguments à passer à QueryRow/Exec,
// et le prochain indice $N disponible (pour la clause WHERE).
// Les extraArgs sont annexés après les args utilisateur.
func (b *queryBuilder) build(extraArgs ...interface{}) (setClauses string, args []interface{}, nextIdx int) {
	return strings.Join(b.clauses, ", "), append(b.args, extraArgs...), b.nextIdx
}
