// Package customers implementa el CRUD de clientes.
package customers

import (
	"context"
	"errors"
	"net/mail"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/jhc/credit-store/server/internal/apperr"
	"github.com/jhc/credit-store/server/internal/database"
	"github.com/jhc/credit-store/server/internal/database/sqlc"
	"github.com/jhc/credit-store/server/internal/domain"
)

const (
	// StatusProspect es un contacto que todavía no es cliente.
	StatusProspect = "prospecto"
	// StatusCustomer es un cliente activo.
	StatusCustomer = "cliente"
	// StatusInPayment es un cliente con un crédito en pago.
	StatusInPayment = "en_pago"
	// StatusSettled es un cliente con su crédito liquidado.
	StatusSettled = "liquidado"
)

// Service contiene la lógica de clientes.
type Service struct {
	store *database.Store
}

// NewService construye el servicio de clientes.
func NewService(store *database.Store) *Service {
	return &Service{store: store}
}

// ListFilter son los filtros y la paginación del listado.
type ListFilter struct {
	Search   string
	Status   string
	Page     int
	PageSize int
}

// Input son los datos editables de un cliente.
type Input struct {
	Name       string
	Address    string
	City       string
	PostalCode string
	Phone      string
	Email      string
	Status     string
}

// List devuelve clientes paginados y el total.
func (s *Service) List(ctx context.Context, filter ListFilter) ([]domain.Customer, int64, error) {
	if filter.Page < 1 {
		filter.Page = 1
	}
	if filter.PageSize < 1 || filter.PageSize > 100 {
		filter.PageSize = 10
	}

	status := strings.TrimSpace(filter.Status)
	if status != "" {
		normalized, ok := normalizeStatus(status)
		if !ok {
			return nil, 0, validationField("status", "El estado no es válido.")
		}
		status = normalized
	}

	params := sqlc.ListCustomersParams{
		Search: optionalString(strings.TrimSpace(filter.Search)),
		Status: optionalString(status),
		Offset: int32((filter.Page - 1) * filter.PageSize),
		Limit:  int32(filter.PageSize),
	}

	rows, err := s.store.Q.ListCustomers(ctx, params)
	if err != nil {
		return nil, 0, apperr.Internal(err)
	}

	total, err := s.store.Q.CountCustomers(ctx, sqlc.CountCustomersParams{
		Search: params.Search,
		Status: params.Status,
	})
	if err != nil {
		return nil, 0, apperr.Internal(err)
	}

	items := make([]domain.Customer, 0, len(rows))
	for _, row := range rows {
		items = append(items, customerFromModel(row))
	}
	return items, total, nil
}

// Get devuelve un cliente por ID.
func (s *Service) Get(ctx context.Context, id uuid.UUID) (domain.Customer, error) {
	row, err := s.store.Q.GetCustomerByID(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Customer{}, apperr.NotFound("Cliente no encontrado.")
	}
	if err != nil {
		return domain.Customer{}, apperr.Internal(err)
	}
	return customerFromModel(row), nil
}

// Create registra un cliente.
func (s *Service) Create(ctx context.Context, in Input) (domain.Customer, error) {
	prepared, err := prepareInput(in)
	if err != nil {
		return domain.Customer{}, err
	}

	row, err := s.store.Q.CreateCustomer(ctx, sqlc.CreateCustomerParams{
		Name:       prepared.Name,
		Address:    optionalString(prepared.Address),
		City:       optionalString(prepared.City),
		PostalCode: optionalString(prepared.PostalCode),
		Phone:      optionalString(prepared.Phone),
		Email:      optionalString(prepared.Email),
		Status:     prepared.Status,
	})
	if err != nil {
		return domain.Customer{}, apperr.Internal(err)
	}
	return customerFromModel(row), nil
}

// Update reemplaza los datos editables de un cliente.
func (s *Service) Update(ctx context.Context, id uuid.UUID, in Input) (domain.Customer, error) {
	prepared, err := prepareInput(in)
	if err != nil {
		return domain.Customer{}, err
	}

	row, err := s.store.Q.UpdateCustomer(ctx, sqlc.UpdateCustomerParams{
		ID:         id,
		Name:       prepared.Name,
		Address:    optionalString(prepared.Address),
		City:       optionalString(prepared.City),
		PostalCode: optionalString(prepared.PostalCode),
		Phone:      optionalString(prepared.Phone),
		Email:      optionalString(prepared.Email),
		Status:     prepared.Status,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Customer{}, apperr.NotFound("Cliente no encontrado.")
	}
	if err != nil {
		return domain.Customer{}, apperr.Internal(err)
	}
	return customerFromModel(row), nil
}

// Delete aplica soft delete al cliente.
func (s *Service) Delete(ctx context.Context, id uuid.UUID) error {
	affected, err := s.store.Q.SoftDeleteCustomer(ctx, id)
	if err != nil {
		return apperr.Internal(err)
	}
	if affected == 0 {
		return apperr.NotFound("Cliente no encontrado.")
	}
	return nil
}

func prepareInput(in Input) (Input, error) {
	name := strings.TrimSpace(in.Name)
	if len(name) < 2 {
		return Input{}, validationField("name", "El nombre debe tener al menos 2 caracteres.")
	}
	if len(name) > 150 {
		return Input{}, validationField("name", "El nombre no puede superar 150 caracteres.")
	}

	address := strings.TrimSpace(in.Address)
	if len(address) > 500 {
		return Input{}, validationField("address", "La dirección no puede superar 500 caracteres.")
	}

	city := strings.TrimSpace(in.City)
	if len(city) > 120 {
		return Input{}, validationField("city", "La ciudad no puede superar 120 caracteres.")
	}

	postalCode := strings.TrimSpace(in.PostalCode)
	if len(postalCode) > 20 {
		return Input{}, validationField("postal_code", "El código postal no puede superar 20 caracteres.")
	}

	phone := strings.TrimSpace(in.Phone)
	if len(phone) > 30 {
		return Input{}, validationField("phone", "El teléfono no puede superar 30 caracteres.")
	}

	email := strings.ToLower(strings.TrimSpace(in.Email))
	if email != "" {
		if len(email) > 254 {
			return Input{}, validationField("email", "El correo no puede superar 254 caracteres.")
		}
		parsed, err := mail.ParseAddress(email)
		if err != nil || parsed.Address != email {
			return Input{}, validationField("email", "Ingresa un correo electrónico válido.")
		}
	}

	status := strings.TrimSpace(in.Status)
	if status == "" {
		status = StatusProspect
	}
	normalized, ok := normalizeStatus(status)
	if !ok {
		return Input{}, validationField("status",
			"El estado debe ser prospecto, cliente, en_pago o liquidado.")
	}

	return Input{
		Name:       name,
		Address:    address,
		City:       city,
		PostalCode: postalCode,
		Phone:      phone,
		Email:      email,
		Status:     normalized,
	}, nil
}

func normalizeStatus(value string) (string, bool) {
	normalized := strings.ToLower(strings.TrimSpace(value))
	normalized = strings.ReplaceAll(normalized, " ", "_")
	normalized = strings.ReplaceAll(normalized, "-", "_")
	switch normalized {
	case StatusProspect, StatusCustomer, StatusInPayment, StatusSettled:
		return normalized, true
	default:
		return "", false
	}
}

func customerFromModel(row sqlc.Customer) domain.Customer {
	return domain.Customer{
		ID:         row.ID,
		Name:       row.Name,
		Address:    row.Address,
		City:       row.City,
		PostalCode: row.PostalCode,
		Phone:      row.Phone,
		Email:      row.Email,
		Status:     row.Status,
		CreatedAt:  row.CreatedAt,
		UpdatedAt:  row.UpdatedAt,
	}
}

func optionalString(value string) *string {
	if value == "" {
		return nil
	}
	return &value
}

func validationField(field, message string) *apperr.Error {
	return apperr.Validation("Datos inválidos.", []apperr.FieldError{{Field: field, Message: message}})
}
