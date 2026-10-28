package auth

import (
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
)

const testSecret = "0123456789abcdef0123456789abcdef"

func TestIssueAndParseToken(t *testing.T) {
	manager := NewTokenManager(testSecret, "credit-store-test", time.Minute)
	userID := uuid.New()
	sessionID := uuid.New()

	token, expiresAt, err := manager.Issue(
		userID,
		sessionID,
		"admin@gmail.com",
		[]string{"admin"},
		[]string{"dashboard.read", "users.read"},
	)
	if err != nil {
		t.Fatalf("Issue() error = %v", err)
	}
	if strings.Count(token, ".") != 2 {
		t.Fatalf("el JWT debe tener 3 segmentos: %s", token)
	}
	if time.Until(expiresAt) <= 0 {
		t.Fatal("la expiración debe estar en el futuro")
	}

	claims, err := manager.Parse(token)
	if err != nil {
		t.Fatalf("Parse() error = %v", err)
	}
	if claims.Subject != userID.String() {
		t.Fatalf("subject = %s, want %s", claims.Subject, userID)
	}
	if claims.SessionID != sessionID.String() {
		t.Fatalf("sid = %s, want %s", claims.SessionID, sessionID)
	}
	if claims.Email != "admin@gmail.com" {
		t.Fatalf("email = %s", claims.Email)
	}
	if len(claims.Permissions) != 2 {
		t.Fatalf("permissions = %v", claims.Permissions)
	}
}

func TestParseRejectsWrongSecret(t *testing.T) {
	issuer := NewTokenManager(testSecret, "credit-store-test", time.Minute)
	token, _, err := issuer.Issue(uuid.New(), uuid.New(), "a@b.com", nil, nil)
	if err != nil {
		t.Fatalf("Issue() error = %v", err)
	}

	other := NewTokenManager("abcdef0123456789abcdef0123456789", "credit-store-test", time.Minute)
	if _, err := other.Parse(token); err == nil {
		t.Fatal("se esperaba error al validar con otro secreto")
	}
}

func TestParseRejectsWrongIssuer(t *testing.T) {
	issuer := NewTokenManager(testSecret, "issuer-a", time.Minute)
	token, _, err := issuer.Issue(uuid.New(), uuid.New(), "a@b.com", nil, nil)
	if err != nil {
		t.Fatalf("Issue() error = %v", err)
	}

	other := NewTokenManager(testSecret, "issuer-b", time.Minute)
	if _, err := other.Parse(token); err == nil {
		t.Fatal("se esperaba error al validar con otro issuer")
	}
}

func TestParseRejectsExpiredToken(t *testing.T) {
	manager := NewTokenManager(testSecret, "credit-store-test", -time.Minute)
	token, _, err := manager.Issue(uuid.New(), uuid.New(), "a@b.com", nil, nil)
	if err != nil {
		t.Fatalf("Issue() error = %v", err)
	}
	if _, err := manager.Parse(token); err == nil {
		t.Fatal("se esperaba error para token expirado")
	}
}

func TestParseRejectsMalformedToken(t *testing.T) {
	manager := NewTokenManager(testSecret, "credit-store-test", time.Minute)
	if _, err := manager.Parse("no-es-un-jwt"); err == nil {
		t.Fatal("se esperaba error para token malformado")
	}
}
