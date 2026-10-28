// Package config carga y valida la configuración del API desde variables de
// entorno (con soporte para .env en desarrollo).
package config

import (
	"fmt"
	"log/slog"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/joho/godotenv"
)

const (
	devJWTSecret = "dev-secret-change-me-please-0123456789abcdef"
	defaultPort  = "8081"
)

// Config es la configuración completa del API.
type Config struct {
	Env         string
	Port        string
	DatabaseURL string

	JWTSecret       string
	JWTIssuer       string
	AccessTokenTTL  time.Duration
	RefreshTokenTTL time.Duration
	BcryptCost      int

	CORSOrigins []string

	AutoMigrate  bool
	SeedOnStart  bool
	SeedPassword string

	// DownloadsDir es la carpeta donde se guardan las fotos de productos.
	// El API la sirve en /downloads.
	DownloadsDir string

	LogLevel slog.Level
}

// Load lee .env (si existe) y valida las variables de entorno.
func Load() (*Config, error) {
	_ = godotenv.Load()

	cfg := &Config{
		Env:             env("APP_ENV", "development"),
		Port:            env("API_PORT", defaultPort),
		DatabaseURL:     env("DATABASE_URL", "postgres://credit_store:credit_store@localhost:5433/credit_store?sslmode=disable"),
		JWTSecret:       env("JWT_SECRET", devJWTSecret),
		JWTIssuer:       env("JWT_ISSUER", "credit-store-api"),
		AccessTokenTTL:  15 * time.Minute,
		RefreshTokenTTL: 7 * 24 * time.Hour,
		BcryptCost:      12,
		SeedPassword:    env("SEED_PASSWORD", "123456"),
		DownloadsDir:    env("DOWNLOADS_DIR", "./downloads"),
	}

	cfg.Env = strings.ToLower(strings.TrimSpace(cfg.Env))
	cfg.Port = strings.TrimPrefix(strings.TrimSpace(cfg.Port), ":")

	var err error
	if cfg.AccessTokenTTL, err = durationEnv("ACCESS_TOKEN_TTL", cfg.AccessTokenTTL); err != nil {
		return nil, err
	}
	if cfg.RefreshTokenTTL, err = durationEnv("REFRESH_TOKEN_TTL", cfg.RefreshTokenTTL); err != nil {
		return nil, err
	}
	if cfg.BcryptCost, err = intEnv("BCRYPT_COST", cfg.BcryptCost); err != nil {
		return nil, err
	}
	if cfg.AutoMigrate, err = boolEnv("AUTO_MIGRATE", true); err != nil {
		return nil, err
	}
	defaultSeed := !cfg.IsProduction()
	if cfg.SeedOnStart, err = boolEnv("SEED_ON_START", defaultSeed); err != nil {
		return nil, err
	}
	if cfg.LogLevel, err = logLevelEnv("LOG_LEVEL", slog.LevelInfo); err != nil {
		return nil, err
	}

	cfg.CORSOrigins = splitCSV(env("CORS_ORIGINS", ""))
	cfg.JWTIssuer = strings.TrimSpace(cfg.JWTIssuer)
	cfg.DownloadsDir = strings.TrimSpace(cfg.DownloadsDir)

	if cfg.Port == "" {
		return nil, fmt.Errorf("API_PORT no puede estar vacío")
	}
	port, err := strconv.Atoi(cfg.Port)
	if err != nil || port < 1 || port > 65535 {
		return nil, fmt.Errorf("API_PORT debe ser un puerto válido (1-65535)")
	}
	if strings.TrimSpace(cfg.DatabaseURL) == "" {
		return nil, fmt.Errorf("DATABASE_URL es obligatoria")
	}
	if len(cfg.JWTSecret) < 32 {
		return nil, fmt.Errorf("JWT_SECRET debe tener al menos 32 caracteres")
	}
	if cfg.IsProduction() && cfg.JWTSecret == devJWTSecret {
		return nil, fmt.Errorf("JWT_SECRET no puede usar el valor de desarrollo en producción")
	}
	if cfg.BcryptCost < 10 || cfg.BcryptCost > 14 {
		return nil, fmt.Errorf("BCRYPT_COST debe estar entre 10 y 14")
	}
	if cfg.AccessTokenTTL < time.Minute || cfg.AccessTokenTTL > 24*time.Hour {
		return nil, fmt.Errorf("ACCESS_TOKEN_TTL debe estar entre 1m y 24h")
	}
	if cfg.RefreshTokenTTL < 24*time.Hour || cfg.RefreshTokenTTL > 90*24*time.Hour {
		return nil, fmt.Errorf("REFRESH_TOKEN_TTL debe estar entre 24h y 2160h")
	}
	if len(cfg.SeedPassword) < 6 || len(cfg.SeedPassword) > 72 {
		return nil, fmt.Errorf("SEED_PASSWORD debe tener entre 6 y 72 caracteres")
	}
	if cfg.DownloadsDir == "" {
		return nil, fmt.Errorf("DOWNLOADS_DIR no puede estar vacío")
	}

	return cfg, nil
}

// Addr devuelve la dirección de escucha HTTP.
func (c *Config) Addr() string {
	return ":" + c.Port
}

// IsProduction indica si el entorno es producción.
func (c *Config) IsProduction() bool {
	return c.Env == "production" || c.Env == "prod"
}

// IsDevelopment indica si el entorno es de desarrollo.
func (c *Config) IsDevelopment() bool {
	return !c.IsProduction()
}

func env(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok && strings.TrimSpace(value) != "" {
		return strings.TrimSpace(value)
	}
	return fallback
}

func durationEnv(key string, fallback time.Duration) (time.Duration, error) {
	value := env(key, "")
	if value == "" {
		return fallback, nil
	}
	parsed, err := time.ParseDuration(value)
	if err != nil {
		return 0, fmt.Errorf("%s no es una duración válida: %w", key, err)
	}
	return parsed, nil
}

func intEnv(key string, fallback int) (int, error) {
	value := env(key, "")
	if value == "" {
		return fallback, nil
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return 0, fmt.Errorf("%s debe ser un número entero: %w", key, err)
	}
	return parsed, nil
}

func boolEnv(key string, fallback bool) (bool, error) {
	value := env(key, "")
	if value == "" {
		return fallback, nil
	}
	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return false, fmt.Errorf("%s debe ser true o false: %w", key, err)
	}
	return parsed, nil
}

func logLevelEnv(key string, fallback slog.Level) (slog.Level, error) {
	value := strings.ToLower(env(key, ""))
	if value == "" {
		return fallback, nil
	}
	switch value {
	case "debug":
		return slog.LevelDebug, nil
	case "info":
		return slog.LevelInfo, nil
	case "warn", "warning":
		return slog.LevelWarn, nil
	case "error":
		return slog.LevelError, nil
	default:
		return 0, fmt.Errorf("%s debe ser debug, info, warn o error", key)
	}
}

func splitCSV(value string) []string {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	items := strings.Split(value, ",")
	result := make([]string, 0, len(items))
	for _, item := range items {
		item = strings.TrimSpace(item)
		if item != "" {
			result = append(result, item)
		}
	}
	return result
}
