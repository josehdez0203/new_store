package auth

import (
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

// Claims son los datos incluidos en el access token. Las autorizaciones se
// resuelven contra la base de datos en cada petición, por lo que los roles y
// permisos del token son informativos.
type Claims struct {
	Email       string   `json:"email,omitempty"`
	SessionID   string   `json:"sid"`
	Roles       []string `json:"roles,omitempty"`
	Permissions []string `json:"permissions,omitempty"`
	jwt.RegisteredClaims
}

// TokenManager firma y valida access tokens JWT HS256.
type TokenManager struct {
	secret []byte
	issuer string
	ttl    time.Duration
}

// NewTokenManager construye el administrador de tokens.
func NewTokenManager(secret, issuer string, ttl time.Duration) *TokenManager {
	return &TokenManager{secret: []byte(secret), issuer: issuer, ttl: ttl}
}

// TTL devuelve la vigencia configurada del access token.
func (m *TokenManager) TTL() time.Duration { return m.ttl }

// Issue genera un access token firmado.
func (m *TokenManager) Issue(
	userID uuid.UUID,
	sessionID uuid.UUID,
	email string,
	roles []string,
	permissions []string,
) (string, time.Time, error) {
	now := time.Now().UTC()
	expiresAt := now.Add(m.ttl)

	claims := Claims{
		Email:       email,
		SessionID:   sessionID.String(),
		Roles:       roles,
		Permissions: permissions,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   userID.String(),
			Issuer:    m.issuer,
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now.Add(-5 * time.Second)),
			ExpiresAt: jwt.NewNumericDate(expiresAt),
			ID:        uuid.NewString(),
		},
	}

	signed, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(m.secret)
	if err != nil {
		return "", time.Time{}, fmt.Errorf("no se pudo firmar el access token: %w", err)
	}
	return signed, expiresAt, nil
}

// Parse valida la firma, expiración e issuer y devuelve los claims.
func (m *TokenManager) Parse(raw string) (*Claims, error) {
	claims := &Claims{}
	token, err := jwt.ParseWithClaims(
		raw,
		claims,
		func(token *jwt.Token) (any, error) {
			if token.Method != jwt.SigningMethodHS256 {
				return nil, fmt.Errorf("método de firma no permitido: %s", token.Method.Alg())
			}
			return m.secret, nil
		},
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithIssuer(m.issuer),
		jwt.WithExpirationRequired(),
		jwt.WithLeeway(30*time.Second),
	)
	if err != nil {
		return nil, err
	}
	if !token.Valid {
		return nil, errors.New("token inválido")
	}
	if claims.Subject == "" || claims.SessionID == "" {
		return nil, errors.New("token incompleto")
	}
	if _, err := uuid.Parse(claims.Subject); err != nil {
		return nil, errors.New("subject inválido")
	}
	if _, err := uuid.Parse(claims.SessionID); err != nil {
		return nil, errors.New("sesión inválida")
	}
	return claims, nil
}
