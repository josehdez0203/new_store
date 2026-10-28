// Package apperr define errores de aplicación con un código estable para el
// API y su correspondiente estado HTTP.
package apperr

import (
	"errors"
	"fmt"
	"net/http"

	"github.com/jackc/pgx/v5/pgconn"
)

// FieldError describe un error de validación asociado a un campo.
type FieldError struct {
	Field   string `json:"field"`
	Message string `json:"message"`
}

// Error es un error de negocio que la capa HTTP puede traducir directamente.
type Error struct {
	Status  int          `json:"-"`
	Code    string       `json:"code"`
	Message string       `json:"message"`
	Details []FieldError `json:"details,omitempty"`
	cause   error
}

// Error implementa la interfaz error.
func (e *Error) Error() string {
	if e.cause != nil {
		return fmt.Sprintf("%s: %s: %v", e.Code, e.Message, e.cause)
	}
	return fmt.Sprintf("%s: %s", e.Code, e.Message)
}

// Unwrap permite usar errors.Is/As con la causa original.
func (e *Error) Unwrap() error { return e.cause }

// WithCause adjunta la causa técnica (no se muestra al cliente).
func (e *Error) WithCause(cause error) *Error {
	e.cause = cause
	return e
}

// WithDetails adjunta errores de validación por campo.
func (e *Error) WithDetails(details ...FieldError) *Error {
	e.Details = append(e.Details, details...)
	return e
}

// New construye un error de aplicación.
func New(status int, code, message string) *Error {
	return &Error{Status: status, Code: code, Message: message}
}

// Validation devuelve un 422 con detalles por campo.
func Validation(message string, details []FieldError) *Error {
	return New(http.StatusUnprocessableEntity, "validation_error", message).WithDetails(details...)
}

// BadRequest devuelve un 400.
func BadRequest(message string) *Error {
	return New(http.StatusBadRequest, "bad_request", message)
}

// Unauthorized devuelve un 401.
func Unauthorized(message string) *Error {
	return New(http.StatusUnauthorized, "unauthorized", message)
}

// Forbidden devuelve un 403.
func Forbidden(message string) *Error {
	return New(http.StatusForbidden, "forbidden", message)
}

// NotFound devuelve un 404.
func NotFound(message string) *Error {
	return New(http.StatusNotFound, "not_found", message)
}

// Conflict devuelve un 409.
func Conflict(message string) *Error {
	return New(http.StatusConflict, "conflict", message)
}

// Internal devuelve un 500 sin filtrar detalles técnicos al cliente.
func Internal(cause error) *Error {
	return New(http.StatusInternalServerError, "internal_error",
		"Ocurrió un error interno. Intenta de nuevo más tarde.").WithCause(cause)
}

// IsUniqueViolation detecta una violación de restricción UNIQUE de Postgres.
func IsUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

// IsForeignKeyViolation detecta una violación de llave foránea de Postgres.
func IsForeignKeyViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23503"
}
