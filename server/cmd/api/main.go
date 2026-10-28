package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/jhc/credit-store/server/internal/auth"
	"github.com/jhc/credit-store/server/internal/config"
	"github.com/jhc/credit-store/server/internal/customers"
	"github.com/jhc/credit-store/server/internal/dashboard"
	"github.com/jhc/credit-store/server/internal/database"
	"github.com/jhc/credit-store/server/internal/products"
	"github.com/jhc/credit-store/server/internal/rbac"
	"github.com/jhc/credit-store/server/internal/sales"
	"github.com/jhc/credit-store/server/internal/seed"
	"github.com/jhc/credit-store/server/internal/server"
	"github.com/jhc/credit-store/server/internal/users"
)

func main() {
	if err := run(); err != nil {
		slog.Error("el API no pudo iniciar", "error", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("configuración inválida: %w", err)
	}

	logger := newLogger(cfg)
	slog.SetDefault(logger)

	downloadsDir, err := filepath.Abs(cfg.DownloadsDir)
	if err != nil {
		return fmt.Errorf("no se pudo resolver DOWNLOADS_DIR: %w", err)
	}
	cfg.DownloadsDir = downloadsDir
	if err := os.MkdirAll(filepath.Join(downloadsDir, "products"), 0o755); err != nil {
		return fmt.Errorf("no se pudo crear DOWNLOADS_DIR: %w", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	logger.Info("iniciando API de ventas a crédito",
		"env", cfg.Env,
		"port", cfg.Port,
		"auto_migrate", cfg.AutoMigrate,
		"seed_on_start", cfg.SeedOnStart,
		"downloads_dir", cfg.DownloadsDir,
	)

	pool, err := database.NewPool(ctx, cfg.DatabaseURL, logger)
	if err != nil {
		return err
	}
	defer pool.Close()

	if cfg.AutoMigrate {
		if err := database.Migrate(ctx, cfg.DatabaseURL, logger); err != nil {
			return err
		}
	}

	store := database.NewStore(pool)

	if cfg.SeedOnStart {
		if err := seed.Run(ctx, store, cfg.BcryptCost, cfg.SeedPassword, logger); err != nil {
			return fmt.Errorf("no se pudieron cargar los datos de prueba: %w", err)
		}
	}

	services := server.Services{
		Auth:      auth.NewService(store, cfg),
		Users:     users.NewService(store, cfg.BcryptCost),
		RBAC:      rbac.NewService(store),
		Dashboard: dashboard.NewService(store),
		Products:  products.NewService(store, cfg.DownloadsDir),
		Customers: customers.NewService(store),
		Sales:     sales.NewService(store),
	}

	router := server.NewRouter(cfg, logger, pool, services)
	httpServer := &http.Server{
		Addr:              cfg.Addr(),
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       60 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	serverErr := make(chan error, 1)
	go func() {
		logger.Info("API escuchando", "addr", cfg.Addr())
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serverErr <- err
		}
	}()

	go cleanupSessions(ctx, services.Auth, logger)

	select {
	case err := <-serverErr:
		return fmt.Errorf("servidor HTTP: %w", err)
	case <-ctx.Done():
		logger.Info("señal de apagado recibida")
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		return fmt.Errorf("error durante el apagado: %w", err)
	}

	logger.Info("API detenida correctamente")
	return nil
}

func newLogger(cfg *config.Config) *slog.Logger {
	options := &slog.HandlerOptions{Level: cfg.LogLevel}
	if cfg.IsProduction() {
		return slog.New(slog.NewJSONHandler(os.Stdout, options))
	}
	return slog.New(slog.NewTextHandler(os.Stdout, options))
}

func cleanupSessions(ctx context.Context, authService *auth.Service, logger *slog.Logger) {
	const interval = 6 * time.Hour
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		deleted, err := authService.CleanupSessions(ctx)
		if err != nil {
			if !errors.Is(err, context.Canceled) {
				logger.Warn("no se pudieron limpiar sesiones antiguas", "error", err)
			}
		} else if deleted > 0 {
			logger.Info("sesiones antiguas eliminadas", "count", deleted)
		}

		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}
