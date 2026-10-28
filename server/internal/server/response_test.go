package server

import (
	"testing"

	"github.com/go-playground/validator/v10"
)

type validationPayload struct {
	Email string `json:"email" binding:"required,email"`
	Name  string `json:"full_name" binding:"required,min=3"`
}

func TestValidationDetailsMapsJSONFields(t *testing.T) {
	validate := validator.New()
	validate.SetTagName("binding")
	err := validate.Struct(validationPayload{Name: "X"})
	if err == nil {
		t.Fatal("se esperaba error de validación")
	}
	validationErrors, ok := err.(validator.ValidationErrors)
	if !ok {
		t.Fatalf("tipo de error inesperado: %T", err)
	}

	details := validationDetails(validationErrors, &validationPayload{})
	if len(details) != 2 {
		t.Fatalf("details = %d, want 2: %+v", len(details), details)
	}

	byField := map[string]string{}
	for _, detail := range details {
		byField[detail.Field] = detail.Message
	}
	if byField["email"] == "" {
		t.Fatalf("falta detalle para email: %+v", details)
	}
	if byField["full_name"] == "" {
		t.Fatalf("falta detalle para full_name: %+v", details)
	}
	if byField["full_name"] != "Debe tener al menos 3 caracteres." {
		t.Fatalf("mensaje inesperado: %s", byField["full_name"])
	}
}
