// Package security agrupa utilidades criptográficas para contraseñas y
// refresh tokens.
package security

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"

	"golang.org/x/crypto/bcrypt"
)

const (
	// MinPasswordLength es la longitud mínima aceptada por el API.
	MinPasswordLength = 6
	// MaxPasswordLength es el límite de bcrypt (72 bytes).
	MaxPasswordLength = 72
)

// HashPassword genera un hash bcrypt con el costo indicado.
func HashPassword(password string, cost int) (string, error) {
	if len(password) < MinPasswordLength {
		return "", fmt.Errorf("la contraseña debe tener al menos %d caracteres", MinPasswordLength)
	}
	if len(password) > MaxPasswordLength {
		return "", fmt.Errorf("la contraseña no puede superar %d bytes", MaxPasswordLength)
	}
	if cost < bcrypt.MinCost || cost > bcrypt.MaxCost {
		return "", fmt.Errorf("costo bcrypt inválido: %d", cost)
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), cost)
	if err != nil {
		return "", err
	}
	return string(hash), nil
}

// VerifyPassword compara una contraseña en texto plano con su hash bcrypt.
func VerifyPassword(hash, password string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
}

// GenerateRefreshToken crea un token opaco aleatorio de 256 bits.
func GenerateRefreshToken() (string, error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", errors.New("no se pudo generar el refresh token")
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}

// HashRefreshToken devuelve el SHA-256 hexadecimal del token. Solo este hash
// se guarda en la base de datos.
func HashRefreshToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}
