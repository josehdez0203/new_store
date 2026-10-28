// Package migrations expone las migraciones SQL embebidas para que el API
// pueda aplicarlas al iniciar sin depender del binario `migrate`.
package migrations

import "embed"

// FS contiene los archivos .up.sql y .down.sql de golang-migrate.
//
//go:embed *.sql
var FS embed.FS
