package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/jhc/credit-store/server/internal/config"
	"github.com/jhc/credit-store/server/internal/database"
	"github.com/jhc/credit-store/server/internal/seed"
)

func main() {
	if err := run(); err != nil {
		slog.Error("no se pudieron cargar los datos de prueba", "error", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("configuración inválida: %w", err)
	}

	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: cfg.LogLevel}))
	slog.SetDefault(logger)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	pool, err := database.NewPool(ctx, cfg.DatabaseURL, logger)
	if err != nil {
		return err
	}
	defer pool.Close()

	if err := database.Migrate(ctx, cfg.DatabaseURL, logger); err != nil {
		return err
	}

	store := database.NewStore(pool)
	if err := seed.Run(ctx, store, cfg.BcryptCost, cfg.SeedPassword, logger); err != nil {
		return err
	}

	logger.Info("seed completado",
		"admin", "admin@gmail.com",
		"password_hint", "usa la contraseña configurada en SEED_PASSWORD",
	)
	return nil
}
