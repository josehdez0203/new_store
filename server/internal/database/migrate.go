package database

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/golang-migrate/migrate/v4"
	pgxmigrate "github.com/golang-migrate/migrate/v4/database/pgx/v5"
	"github.com/golang-migrate/migrate/v4/source/iofs"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/stdlib"

	"github.com/jhc/credit-store/server/db/migrations"
)

// Migrate aplica las migraciones embebidas usando golang-migrate.
// Es idempotente: si el esquema ya está al día devuelve nil.
func Migrate(ctx context.Context, databaseURL string, log *slog.Logger) error {
	if err := ctx.Err(); err != nil {
		return err
	}

	cfg, err := pgx.ParseConfig(databaseURL)
	if err != nil {
		return fmt.Errorf("DATABASE_URL inválida para migraciones: %w", err)
	}
	sqlDB := stdlib.OpenDB(*cfg)
	defer sqlDB.Close()

	pingCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if err := sqlDB.PingContext(pingCtx); err != nil {
		return fmt.Errorf("no se pudo conectar para migrar: %w", err)
	}

	driver, err := pgxmigrate.WithInstance(sqlDB, &pgxmigrate.Config{})
	if err != nil {
		return fmt.Errorf("no se pudo crear el driver de migraciones: %w", err)
	}

	source, err := iofs.New(migrations.FS, ".")
	if err != nil {
		return fmt.Errorf("no se pudieron leer las migraciones embebidas: %w", err)
	}

	m, err := migrate.NewWithInstance("iofs", source, "pgx5", driver)
	if err != nil {
		return fmt.Errorf("no se pudo inicializar golang-migrate: %w", err)
	}
	defer func() {
		if sourceErr, dbErr := m.Close(); sourceErr != nil || dbErr != nil {
			log.Debug("cierre de migraciones", "source_error", sourceErr, "db_error", dbErr)
		}
	}()

	if err := m.Up(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
		return fmt.Errorf("error aplicando migraciones: %w", err)
	}

	version, dirty, err := m.Version()
	if err != nil && !errors.Is(err, migrate.ErrNilVersion) {
		return fmt.Errorf("no se pudo leer la versión del esquema: %w", err)
	}
	if dirty {
		return fmt.Errorf("el esquema quedó en estado dirty en la versión %d; revisa las migraciones", version)
	}
	log.Info("migraciones al día", "version", version)
	return nil
}
