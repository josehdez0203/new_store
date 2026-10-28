// Package auth implementa login, refresh tokens rotativos, cierre de sesión y
// resolución del contexto de autorización.
package auth

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/jhc/credit-store/server/internal/apperr"
	"github.com/jhc/credit-store/server/internal/config"
	"github.com/jhc/credit-store/server/internal/database"
	"github.com/jhc/credit-store/server/internal/database/sqlc"
	"github.com/jhc/credit-store/server/internal/domain"
	"github.com/jhc/credit-store/server/internal/security"
)

// Service contiene la lógica de autenticación.
type Service struct {
	store  *database.Store
	cfg    *config.Config
	tokens *TokenManager
}

// NewService construye el servicio de autenticación.
func NewService(store *database.Store, cfg *config.Config) *Service {
	return &Service{
		store:  store,
		cfg:    cfg,
		tokens: NewTokenManager(cfg.JWTSecret, cfg.JWTIssuer, cfg.AccessTokenTTL),
	}
}

// LoginInput son los datos del inicio de sesión.
type LoginInput struct {
	Email     string
	Password  string
	UserAgent string
	IP        string
}

// ProfileInput permite actualizar el perfil propio.
type ProfileInput struct {
	FullName *string
	Email    *string
}

// LoginResult es el resultado de un login o refresh exitoso.
type LoginResult struct {
	Tokens    domain.Tokens
	User      domain.User
	SessionID uuid.UUID
}

// Login valida credenciales y crea una nueva sesión con refresh token.
func (s *Service) Login(ctx context.Context, in LoginInput) (*LoginResult, error) {
	email := normalizeEmail(in.Email)

	user, err := s.store.Q.GetUserByEmail(ctx, email)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, invalidCredentials()
	}
	if err != nil {
		return nil, apperr.Internal(err)
	}
	if !security.VerifyPassword(user.PasswordHash, in.Password) {
		return nil, invalidCredentials()
	}
	if !user.IsActive {
		return nil, apperr.New(http.StatusForbidden, "account_inactive",
			"Tu cuenta está desactivada. Contacta al administrador.")
	}

	refreshToken, err := security.GenerateRefreshToken()
	if err != nil {
		return nil, apperr.Internal(err)
	}

	expiresAt := time.Now().UTC().Add(s.cfg.RefreshTokenTTL)
	session, err := s.store.Q.CreateSession(ctx, sqlc.CreateSessionParams{
		UserID:           user.ID,
		RefreshTokenHash: security.HashRefreshToken(refreshToken),
		UserAgent:        nullableString(in.UserAgent),
		IpAddress:        nullableString(in.IP),
		ExpiresAt:        expiresAt,
	})
	if err != nil {
		return nil, apperr.Internal(err)
	}

	access, err := s.store.Q.GetUserAccess(ctx, user.ID)
	if err != nil {
		return nil, apperr.Internal(err)
	}

	accessToken, accessExpiresAt, err := s.tokens.Issue(
		user.ID, session.ID, access.Email, access.Roles, access.Permissions,
	)
	if err != nil {
		return nil, apperr.Internal(err)
	}

	// La marca de último acceso no debe impedir el login.
	_ = s.store.Q.TouchLastLogin(ctx, user.ID)

	return &LoginResult{
		Tokens: domain.Tokens{
			AccessToken:      accessToken,
			RefreshToken:     refreshToken,
			AccessExpiresAt:  accessExpiresAt,
			RefreshExpiresAt: session.ExpiresAt,
		},
		User:      userFromAccess(access),
		SessionID: session.ID,
	}, nil
}

// Refresh rota el refresh token y emite un nuevo par de tokens.
func (s *Service) Refresh(ctx context.Context, refreshToken, userAgent, ip string) (*LoginResult, error) {
	refreshToken = strings.TrimSpace(refreshToken)
	if refreshToken == "" {
		return nil, invalidRefreshToken()
	}

	session, err := s.store.Q.GetSessionByRefreshToken(ctx, security.HashRefreshToken(refreshToken))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, invalidRefreshToken()
	}
	if err != nil {
		return nil, apperr.Internal(err)
	}
	now := time.Now().UTC()
	if session.RevokedAt != nil || !session.ExpiresAt.After(now) {
		return nil, invalidRefreshToken()
	}

	access, err := s.store.Q.GetUserAccess(ctx, session.UserID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, invalidRefreshToken()
	}
	if err != nil {
		return nil, apperr.Internal(err)
	}
	if !access.IsActive {
		return nil, apperr.Forbidden("Tu cuenta está desactivada. Contacta al administrador.")
	}

	newRefreshToken, err := security.GenerateRefreshToken()
	if err != nil {
		return nil, apperr.Internal(err)
	}
	newExpiresAt := now.Add(s.cfg.RefreshTokenTTL)

	rotated, err := s.store.Q.RotateSessionRefreshToken(ctx, sqlc.RotateSessionRefreshTokenParams{
		ID:               session.ID,
		RefreshTokenHash: security.HashRefreshToken(newRefreshToken),
		ExpiresAt:        newExpiresAt,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, invalidRefreshToken()
	}
	if err != nil {
		return nil, apperr.Internal(err)
	}

	accessToken, accessExpiresAt, err := s.tokens.Issue(
		session.UserID, rotated.ID, access.Email, access.Roles, access.Permissions,
	)
	if err != nil {
		return nil, apperr.Internal(err)
	}

	return &LoginResult{
		Tokens: domain.Tokens{
			AccessToken:      accessToken,
			RefreshToken:     newRefreshToken,
			AccessExpiresAt:  accessExpiresAt,
			RefreshExpiresAt: rotated.ExpiresAt,
		},
		User:      userFromAccess(access),
		SessionID: rotated.ID,
	}, nil
}

// Logout revoca la sesión actual.
func (s *Service) Logout(ctx context.Context, userID, sessionID uuid.UUID) error {
	if _, err := s.store.Q.RevokeUserSession(ctx, sqlc.RevokeUserSessionParams{
		ID:     sessionID,
		UserID: userID,
	}); err != nil {
		return apperr.Internal(err)
	}
	return nil
}

// LogoutAll revoca todas las sesiones del usuario, incluida la actual.
func (s *Service) LogoutAll(ctx context.Context, userID uuid.UUID) error {
	if _, err := s.store.Q.RevokeAllUserSessions(ctx, userID); err != nil {
		return apperr.Internal(err)
	}
	return nil
}

// Me devuelve el usuario con roles y permisos frescos.
func (s *Service) Me(ctx context.Context, userID uuid.UUID) (domain.User, error) {
	access, err := s.store.Q.GetUserAccess(ctx, userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.User{}, apperr.NotFound("Usuario no encontrado.")
	}
	if err != nil {
		return domain.User{}, apperr.Internal(err)
	}
	return userFromAccess(access), nil
}

// GetAuthContext resuelve la sesión y el usuario para el middleware.
func (s *Service) GetAuthContext(ctx context.Context, sessionID uuid.UUID) (*domain.AuthContext, error) {
	row, err := s.store.Q.GetAuthContext(ctx, sessionID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, apperr.New(http.StatusUnauthorized, "invalid_session",
			"La sesión es inválida o ha expirado. Inicia sesión de nuevo.")
	}
	if err != nil {
		return nil, apperr.Internal(err)
	}

	return &domain.AuthContext{
		User: domain.User{
			ID:          row.ID,
			Email:       row.Email,
			FullName:    row.FullName,
			IsActive:    row.IsActive,
			Roles:       nonNil(row.Roles),
			Permissions: nonNil(row.Permissions),
			LastLoginAt: row.LastLoginAt,
			CreatedAt:   row.CreatedAt,
			UpdatedAt:   row.UpdatedAt,
		},
		SessionID:        row.SessionID,
		SessionExpiresAt: row.SessionExpiresAt,
	}, nil
}

// UpdateProfile actualiza nombre y/o correo del usuario autenticado.
func (s *Service) UpdateProfile(ctx context.Context, userID uuid.UUID, in ProfileInput) (domain.User, error) {
	if in.FullName == nil && in.Email == nil {
		return domain.User{}, apperr.BadRequest("No hay campos para actualizar.")
	}

	params := sqlc.UpdateUserParams{ID: userID}

	if in.FullName != nil {
		fullName := strings.TrimSpace(*in.FullName)
		if len(fullName) < 2 {
			return domain.User{}, apperr.Validation("Datos inválidos.", []apperr.FieldError{
				{Field: "full_name", Message: "El nombre debe tener al menos 2 caracteres."},
			})
		}
		params.FullName = &fullName
	}

	if in.Email != nil {
		email := normalizeEmail(*in.Email)
		if email == "" {
			return domain.User{}, apperr.Validation("Datos inválidos.", []apperr.FieldError{
				{Field: "email", Message: "El correo es obligatorio."},
			})
		}
		exists, err := s.store.Q.UserEmailExists(ctx, sqlc.UserEmailExistsParams{
			Email: email,
			ID:    userID,
		})
		if err != nil {
			return domain.User{}, apperr.Internal(err)
		}
		if exists {
			return domain.User{}, apperr.Conflict("El correo ya está registrado por otro usuario.")
		}
		params.Email = &email
	}

	if _, err := s.store.Q.UpdateUser(ctx, params); err != nil {
		if apperr.IsUniqueViolation(err) {
			return domain.User{}, apperr.Conflict("El correo ya está registrado por otro usuario.")
		}
		return domain.User{}, apperr.Internal(err)
	}

	return s.Me(ctx, userID)
}

// ChangePassword cambia la contraseña y revoca las demás sesiones.
func (s *Service) ChangePassword(ctx context.Context, userID, currentSessionID uuid.UUID, currentPassword, newPassword string) error {
	user, err := s.store.Q.GetUserByID(ctx, userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return apperr.NotFound("Usuario no encontrado.")
	}
	if err != nil {
		return apperr.Internal(err)
	}

	if !security.VerifyPassword(user.PasswordHash, currentPassword) {
		return apperr.New(http.StatusBadRequest, "invalid_current_password",
			"La contraseña actual no es correcta.")
	}
	if currentPassword == newPassword {
		return apperr.BadRequest("La nueva contraseña debe ser diferente a la actual.")
	}

	hash, err := security.HashPassword(newPassword, s.cfg.BcryptCost)
	if err != nil {
		return apperr.Internal(err)
	}

	err = s.store.WithTx(ctx, func(q *sqlc.Queries) error {
		if _, err := q.UpdateUser(ctx, sqlc.UpdateUserParams{
			ID:           userID,
			PasswordHash: &hash,
		}); err != nil {
			return err
		}
		if _, err := q.RevokeOtherUserSessions(ctx, sqlc.RevokeOtherUserSessionsParams{
			UserID: userID,
			ID:     currentSessionID,
		}); err != nil {
			return err
		}
		return nil
	})
	if err != nil {
		return apperr.Internal(err)
	}
	return nil
}

// ListSessions devuelve las sesiones activas del usuario.
func (s *Service) ListSessions(ctx context.Context, userID uuid.UUID) ([]domain.Session, error) {
	rows, err := s.store.Q.ListUserSessions(ctx, userID)
	if err != nil {
		return nil, apperr.Internal(err)
	}

	sessions := make([]domain.Session, 0, len(rows))
	for _, row := range rows {
		sessions = append(sessions, domain.Session{
			ID:         row.ID,
			UserAgent:  row.UserAgent,
			IPAddress:  row.IpAddress,
			ExpiresAt:  row.ExpiresAt,
			RevokedAt:  row.RevokedAt,
			LastUsedAt: row.LastUsedAt,
			CreatedAt:  row.CreatedAt,
		})
	}
	return sessions, nil
}

// RevokeSession revoca una sesión del propio usuario.
func (s *Service) RevokeSession(ctx context.Context, userID, sessionID uuid.UUID) error {
	affected, err := s.store.Q.RevokeUserSession(ctx, sqlc.RevokeUserSessionParams{
		ID:     sessionID,
		UserID: userID,
	})
	if err != nil {
		return apperr.Internal(err)
	}
	if affected == 0 {
		return apperr.NotFound("Sesión no encontrada.")
	}
	return nil
}

// ParseAccessToken valida un access token y devuelve sus claims.
func (s *Service) ParseAccessToken(raw string) (*Claims, error) {
	return s.tokens.Parse(raw)
}

// AccessTokenTTL devuelve la vigencia del access token.
func (s *Service) AccessTokenTTL() time.Duration { return s.tokens.TTL() }

// CleanupSessions elimina sesiones antiguas (más de 30 días).
func (s *Service) CleanupSessions(ctx context.Context) (int64, error) {
	return s.store.Q.DeleteStaleSessions(ctx)
}

func invalidCredentials() error {
	return apperr.New(http.StatusUnauthorized, "invalid_credentials", "Correo o contraseña incorrectos.")
}

func invalidRefreshToken() error {
	return apperr.New(http.StatusUnauthorized, "invalid_refresh_token",
		"El refresh token es inválido o ha expirado. Inicia sesión de nuevo.")
}

func normalizeEmail(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}

func nullableString(value string) *string {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	return &value
}

func nonNil(values []string) []string {
	if values == nil {
		return []string{}
	}
	return values
}

func userFromAccess(row sqlc.GetUserAccessRow) domain.User {
	return domain.User{
		ID:          row.ID,
		Email:       row.Email,
		FullName:    row.FullName,
		IsActive:    row.IsActive,
		Roles:       nonNil(row.Roles),
		Permissions: nonNil(row.Permissions),
		LastLoginAt: row.LastLoginAt,
		CreatedAt:   row.CreatedAt,
		UpdatedAt:   row.UpdatedAt,
	}
}
