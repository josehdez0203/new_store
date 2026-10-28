package security

import (
	"strings"
	"testing"
)

func TestHashAndVerifyPassword(t *testing.T) {
	hash, err := HashPassword("123456", 10)
	if err != nil {
		t.Fatalf("HashPassword() error = %v", err)
	}
	if hash == "123456" {
		t.Fatal("la contraseña no debe almacenarse en texto plano")
	}
	if !VerifyPassword(hash, "123456") {
		t.Fatal("VerifyPassword() debería aceptar la contraseña correcta")
	}
	if VerifyPassword(hash, "654321") {
		t.Fatal("VerifyPassword() no debería aceptar una contraseña incorrecta")
	}
}

func TestHashPasswordRejectsInvalidLengths(t *testing.T) {
	if _, err := HashPassword("123", 10); err == nil {
		t.Fatal("se esperaba error para contraseña corta")
	}
	long := strings.Repeat("a", MaxPasswordLength+1)
	if _, err := HashPassword(long, 10); err == nil {
		t.Fatal("se esperaba error para contraseña mayor a bcrypt")
	}
}

func TestRefreshTokenGenerationAndHash(t *testing.T) {
	first, err := GenerateRefreshToken()
	if err != nil {
		t.Fatalf("GenerateRefreshToken() error = %v", err)
	}
	second, err := GenerateRefreshToken()
	if err != nil {
		t.Fatalf("GenerateRefreshToken() error = %v", err)
	}
	if first == second {
		t.Fatal("los refresh tokens deben ser únicos")
	}
	if len(first) < 40 {
		t.Fatalf("refresh token demasiado corto: %d", len(first))
	}

	hash := HashRefreshToken(first)
	if len(hash) != 64 {
		t.Fatalf("el hash SHA-256 debe medir 64 hex chars, mide %d", len(hash))
	}
	if hash != HashRefreshToken(first) {
		t.Fatal("el hash debe ser determinista")
	}
	if hash == first {
		t.Fatal("el hash no debe ser igual al token")
	}
}
