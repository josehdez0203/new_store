// Package sales implementa ventas, cotizaciones y planes de pago.
package sales

import (
	"context"
	"errors"
	"math"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/jhc/credit-store/server/internal/apperr"
	"github.com/jhc/credit-store/server/internal/database"
	"github.com/jhc/credit-store/server/internal/database/sqlc"
	"github.com/jhc/credit-store/server/internal/domain"
)

const (
	StatusQuote    = "cotizacion"
	StatusSale     = "venta"
	StatusCanceled = "cancelada"

	PaymentCash   = "contado"
	PaymentCredit = "credito"
)

// Service contiene la lógica de ventas y financiamiento.
type Service struct {
	store *database.Store
}

// NewService construye el servicio.
func NewService(store *database.Store) *Service {
	return &Service{store: store}
}

// ListFilter son los filtros del listado.
type ListFilter struct {
	Search   string
	Status   string
	SellerID *uuid.UUID
	Page     int
	PageSize int
}

// ItemInput es una partida solicitada.
type ItemInput struct {
	ProductID uuid.UUID
	Quantity  int32
}

// CreateInput son los datos para registrar una venta o cotización.
type CreateInput struct {
	ClientID           uuid.UUID
	SellerID           uuid.UUID
	SaleDate           time.Time
	Status             string
	PaymentType        string
	DownPaymentPercent float64
	Months             int32
	Items              []ItemInput
}

// CreditSettingsInput son los parámetros editables por el admin.
type CreditSettingsInput struct {
	DownPaymentOptions  []float64
	CreditMonths        []int32
	MonthlyInterestRate float64
}

type creditPlan struct {
	DownPaymentPercent  float64
	DownPayment         float64
	FinancedAmount      float64
	MonthlyInterestRate float64
	Months              int32
	TotalInterest       float64
	Payments            []domain.SalePayment
}

// List devuelve ventas paginadas.
func (s *Service) List(ctx context.Context, filter ListFilter) ([]domain.Sale, int64, error) {
	if filter.Page < 1 {
		filter.Page = 1
	}
	if filter.PageSize < 1 || filter.PageSize > 100 {
		filter.PageSize = 10
	}
	status := strings.TrimSpace(filter.Status)
	if status != "" && !validStatus(status) {
		return nil, 0, validationField("status", "El estado no es válido.")
	}

	params := sqlc.ListSalesParams{
		Search:   optionalString(strings.TrimSpace(filter.Search)),
		Status:   optionalString(status),
		SellerID: filter.SellerID,
		Offset:   int32((filter.Page - 1) * filter.PageSize),
		Limit:    int32(filter.PageSize),
	}
	rows, err := s.store.Q.ListSales(ctx, params)
	if err != nil {
		return nil, 0, apperr.Internal(err)
	}
	total, err := s.store.Q.CountSales(ctx, sqlc.CountSalesParams{
		Search:   params.Search,
		Status:   params.Status,
		SellerID: params.SellerID,
	})
	if err != nil {
		return nil, 0, apperr.Internal(err)
	}

	items := make([]domain.Sale, 0, len(rows))
	for _, row := range rows {
		items = append(items, saleFromListRow(row))
	}
	return items, total, nil
}

// Get devuelve una venta con su detalle y plan de pagos.
func (s *Service) Get(ctx context.Context, id uuid.UUID) (domain.Sale, error) {
	row, err := s.store.Q.GetSaleByID(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Sale{}, apperr.NotFound("Venta no encontrada.")
	}
	if err != nil {
		return domain.Sale{}, apperr.Internal(err)
	}
	sale := saleFromGetRow(row)

	itemRows, err := s.store.Q.ListSaleItems(ctx, id)
	if err != nil {
		return domain.Sale{}, apperr.Internal(err)
	}
	sale.Items = make([]domain.SaleItem, 0, len(itemRows))
	for _, item := range itemRows {
		sale.Items = append(sale.Items, domain.SaleItem{
			ID:          item.ID,
			ProductID:   item.ProductID,
			ProductName: item.ProductName,
			Quantity:    item.Quantity,
			UnitPrice:   item.UnitPrice,
			Subtotal:    numericToFloat(item.Subtotal),
		})
	}

	paymentRows, err := s.store.Q.ListSalePayments(ctx, id)
	if err != nil {
		return domain.Sale{}, apperr.Internal(err)
	}
	sale.Payments = make([]domain.SalePayment, 0, len(paymentRows))
	for _, payment := range paymentRows {
		sale.Payments = append(sale.Payments, domain.SalePayment{
			ID:                payment.ID,
			InstallmentNumber: payment.InstallmentNumber,
			Kind:              payment.Kind,
			DueDate:           payment.DueDate.Time,
			Amount:            payment.Amount,
		})
	}
	return sale, nil
}

// Create registra una venta o cotización y genera su plan de pagos.
func (s *Service) Create(ctx context.Context, in CreateInput) (domain.Sale, error) {
	if !validStatus(in.Status) || in.Status == StatusCanceled {
		return domain.Sale{}, validationField("status", "El estado debe ser cotizacion o venta.")
	}
	if in.PaymentType != PaymentCash && in.PaymentType != PaymentCredit {
		return domain.Sale{}, validationField("payment_type", "El tipo de pago debe ser contado o credito.")
	}
	if len(in.Items) == 0 {
		return domain.Sale{}, validationField("items", "Agrega al menos un producto.")
	}
	if len(in.Items) > 50 {
		return domain.Sale{}, validationField("items", "Una venta no puede tener más de 50 partidas.")
	}

	client, err := s.store.Q.GetCustomerByID(ctx, in.ClientID)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Sale{}, validationField("client_id", "El cliente no existe.")
	}
	if err != nil {
		return domain.Sale{}, apperr.Internal(err)
	}

	isSeller, err := s.store.Q.IsUserSeller(ctx, in.SellerID)
	if err != nil {
		return domain.Sale{}, apperr.Internal(err)
	}
	if !isSeller {
		return domain.Sale{}, validationField("seller_id", "El vendedor no existe o no tiene el rol vendedor.")
	}

	seen := make(map[uuid.UUID]struct{}, len(in.Items))
	prices := make(map[uuid.UUID]float64, len(in.Items))
	for _, item := range in.Items {
		if item.Quantity <= 0 {
			return domain.Sale{}, validationField("items", "La cantidad de cada producto debe ser mayor que cero.")
		}
		if _, exists := seen[item.ProductID]; exists {
			return domain.Sale{}, validationField("items", "No repitas el mismo producto en la venta.")
		}
		seen[item.ProductID] = struct{}{}
		product, err := s.store.Q.GetProductByID(ctx, item.ProductID)
		if errors.Is(err, pgx.ErrNoRows) {
			return domain.Sale{}, validationField("items", "Uno de los productos no existe.")
		}
		if err != nil {
			return domain.Sale{}, apperr.Internal(err)
		}
		prices[item.ProductID] = product.Price
	}

	var planSettings domain.CreditSettings
	if in.PaymentType == PaymentCredit {
		settings, err := s.GetCreditSettings(ctx)
		if err != nil {
			return domain.Sale{}, err
		}
		planSettings = settings
		validDown := false
		for _, option := range settings.DownPaymentOptions {
			if math.Abs(option-in.DownPaymentPercent) < 0.001 {
				validDown = true
				break
			}
		}
		if !validDown {
			return domain.Sale{}, validationField("down_payment_percent", "Selecciona un anticipo permitido por la empresa.")
		}
		validMonths := false
		for _, months := range settings.CreditMonths {
			if months == in.Months {
				validMonths = true
				break
			}
		}
		if !validMonths {
			return domain.Sale{}, validationField("months", "Selecciona un plazo permitido por la empresa.")
		}
		if in.DownPaymentPercent >= 100 {
			return domain.Sale{}, validationField("down_payment_percent", "El anticipo debe ser menor al total.")
		}
	}

	if in.SaleDate.IsZero() {
		in.SaleDate = time.Now()
	}
	saleDate := dateOnly(in.SaleDate)

	var saleID uuid.UUID
	err = s.store.WithTx(ctx, func(q *sqlc.Queries) error {
		created, err := q.CreateSale(ctx, sqlc.CreateSaleParams{
			ClientID:    client.ID,
			SellerID:    in.SellerID,
			SaleDate:    pgtype.Date{Time: saleDate, Valid: true},
			Status:      in.Status,
			PaymentType: in.PaymentType,
		})
		if err != nil {
			return apperr.Internal(err)
		}
		saleID = created.ID

		for _, item := range in.Items {
			if _, err := q.CreateSaleItem(ctx, sqlc.CreateSaleItemParams{
				SaleID:    created.ID,
				ProductID: item.ProductID,
				Quantity:  item.Quantity,
				UnitPrice: prices[item.ProductID],
			}); err != nil {
				return apperr.Internal(err)
			}
		}

		// El trigger actualizó sales.total a partir de las partidas.
		row, err := q.GetSaleByID(ctx, created.ID)
		if err != nil {
			return apperr.Internal(err)
		}
		total := row.Total

		var plan creditPlan
		if in.PaymentType == PaymentCash {
			plan = creditPlan{
				Payments: []domain.SalePayment{{
					InstallmentNumber: 1,
					Kind:              "contado",
					DueDate:           saleDate,
					Amount:            roundMoney(total),
				}},
			}
		} else {
			plan = buildCreditPlan(total, in.DownPaymentPercent, in.Months, planSettings.MonthlyInterestRate, saleDate)
		}

		if _, err := q.UpdateSalePlan(ctx, sqlc.UpdateSalePlanParams{
			ID:                  created.ID,
			DownPaymentPercent:  plan.DownPaymentPercent,
			DownPayment:         plan.DownPayment,
			FinancedAmount:      plan.FinancedAmount,
			MonthlyInterestRate: plan.MonthlyInterestRate,
			Months:              plan.Months,
			TotalInterest:       plan.TotalInterest,
		}); err != nil {
			return apperr.Internal(err)
		}

		for _, payment := range plan.Payments {
			if _, err := q.CreateSalePayment(ctx, sqlc.CreateSalePaymentParams{
				SaleID:            created.ID,
				InstallmentNumber: payment.InstallmentNumber,
				Kind:              payment.Kind,
				DueDate:           pgtype.Date{Time: dateOnly(payment.DueDate), Valid: true},
				Amount:            payment.Amount,
			}); err != nil {
				return apperr.Internal(err)
			}
		}
		return nil
	})
	if err != nil {
		return domain.Sale{}, err
	}
	return s.Get(ctx, saleID)
}

// Update reemplaza los datos editables de una venta y regenera su plan.
func (s *Service) Update(ctx context.Context, id uuid.UUID, in CreateInput) (domain.Sale, error) {
	existing, err := s.store.Q.GetSaleByID(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Sale{}, apperr.NotFound("Venta no encontrada.")
	}
	if err != nil {
		return domain.Sale{}, apperr.Internal(err)
	}
	if existing.Status == StatusCanceled {
		return domain.Sale{}, apperr.Conflict("No se puede editar una venta cancelada.")
	}
	if !validStatus(in.Status) || in.Status == StatusCanceled {
		return domain.Sale{}, validationField("status", "El estado debe ser cotizacion o venta.")
	}
	if in.PaymentType != PaymentCash && in.PaymentType != PaymentCredit {
		return domain.Sale{}, validationField("payment_type", "El tipo de pago debe ser contado o credito.")
	}
	if len(in.Items) == 0 {
		return domain.Sale{}, validationField("items", "Agrega al menos un producto.")
	}
	if len(in.Items) > 50 {
		return domain.Sale{}, validationField("items", "Una venta no puede tener más de 50 partidas.")
	}

	client, err := s.store.Q.GetCustomerByID(ctx, in.ClientID)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Sale{}, validationField("client_id", "El cliente no existe.")
	}
	if err != nil {
		return domain.Sale{}, apperr.Internal(err)
	}

	isSeller, err := s.store.Q.IsUserSeller(ctx, in.SellerID)
	if err != nil {
		return domain.Sale{}, apperr.Internal(err)
	}
	if !isSeller {
		return domain.Sale{}, validationField("seller_id", "El vendedor no existe o no tiene el rol vendedor.")
	}

	seen := make(map[uuid.UUID]struct{}, len(in.Items))
	prices := make(map[uuid.UUID]float64, len(in.Items))
	for _, item := range in.Items {
		if item.Quantity <= 0 {
			return domain.Sale{}, validationField("items", "La cantidad de cada producto debe ser mayor que cero.")
		}
		if _, exists := seen[item.ProductID]; exists {
			return domain.Sale{}, validationField("items", "No repitas el mismo producto en la venta.")
		}
		seen[item.ProductID] = struct{}{}
		product, err := s.store.Q.GetProductByID(ctx, item.ProductID)
		if errors.Is(err, pgx.ErrNoRows) {
			return domain.Sale{}, validationField("items", "Uno de los productos no existe.")
		}
		if err != nil {
			return domain.Sale{}, apperr.Internal(err)
		}
		prices[item.ProductID] = product.Price
	}

	var planSettings domain.CreditSettings
	if in.PaymentType == PaymentCredit {
		settings, err := s.GetCreditSettings(ctx)
		if err != nil {
			return domain.Sale{}, err
		}
		planSettings = settings
		validDown := false
		for _, option := range settings.DownPaymentOptions {
			if math.Abs(option-in.DownPaymentPercent) < 0.001 {
				validDown = true
				break
			}
		}
		if !validDown {
			return domain.Sale{}, validationField("down_payment_percent", "Selecciona un anticipo permitido por la empresa.")
		}
		validMonths := false
		for _, months := range settings.CreditMonths {
			if months == in.Months {
				validMonths = true
				break
			}
		}
		if !validMonths {
			return domain.Sale{}, validationField("months", "Selecciona un plazo permitido por la empresa.")
		}
		if in.DownPaymentPercent >= 100 {
			return domain.Sale{}, validationField("down_payment_percent", "El anticipo debe ser menor al total.")
		}
	}

	if in.SaleDate.IsZero() {
		in.SaleDate = time.Now()
	}
	saleDate := dateOnly(in.SaleDate)

	err = s.store.WithTx(ctx, func(q *sqlc.Queries) error {
		if _, err := q.UpdateSale(ctx, sqlc.UpdateSaleParams{
			ID:          id,
			ClientID:    client.ID,
			SellerID:    in.SellerID,
			SaleDate:    pgtype.Date{Time: saleDate, Valid: true},
			Status:      in.Status,
			PaymentType: in.PaymentType,
		}); err != nil {
			return apperr.Internal(err)
		}
		if err := q.DeleteSaleItems(ctx, id); err != nil {
			return apperr.Internal(err)
		}
		if err := q.DeleteSalePayments(ctx, id); err != nil {
			return apperr.Internal(err)
		}
		for _, item := range in.Items {
			if _, err := q.CreateSaleItem(ctx, sqlc.CreateSaleItemParams{
				SaleID:    id,
				ProductID: item.ProductID,
				Quantity:  item.Quantity,
				UnitPrice: prices[item.ProductID],
			}); err != nil {
				return apperr.Internal(err)
			}
		}

		row, err := q.GetSaleByID(ctx, id)
		if err != nil {
			return apperr.Internal(err)
		}
		total := row.Total

		var plan creditPlan
		if in.PaymentType == PaymentCash {
			plan = creditPlan{
				Payments: []domain.SalePayment{{
					InstallmentNumber: 1,
					Kind:              "contado",
					DueDate:           saleDate,
					Amount:            roundMoney(total),
				}},
			}
		} else {
			plan = buildCreditPlan(total, in.DownPaymentPercent, in.Months, planSettings.MonthlyInterestRate, saleDate)
		}

		if _, err := q.UpdateSalePlan(ctx, sqlc.UpdateSalePlanParams{
			ID:                  id,
			DownPaymentPercent:  plan.DownPaymentPercent,
			DownPayment:         plan.DownPayment,
			FinancedAmount:      plan.FinancedAmount,
			MonthlyInterestRate: plan.MonthlyInterestRate,
			Months:              plan.Months,
			TotalInterest:       plan.TotalInterest,
		}); err != nil {
			return apperr.Internal(err)
		}
		for _, payment := range plan.Payments {
			if _, err := q.CreateSalePayment(ctx, sqlc.CreateSalePaymentParams{
				SaleID:            id,
				InstallmentNumber: payment.InstallmentNumber,
				Kind:              payment.Kind,
				DueDate:           pgtype.Date{Time: dateOnly(payment.DueDate), Valid: true},
				Amount:            payment.Amount,
			}); err != nil {
				return apperr.Internal(err)
			}
		}
		return nil
	})
	if err != nil {
		return domain.Sale{}, err
	}
	return s.Get(ctx, id)
}

// UpdateStatus cambia el estado de una venta.
func (s *Service) UpdateStatus(ctx context.Context, id uuid.UUID, status string) (domain.Sale, error) {
	if !validStatus(status) {
		return domain.Sale{}, validationField("status", "El estado no es válido.")
	}
	_, err := s.store.Q.UpdateSaleStatus(ctx, sqlc.UpdateSaleStatusParams{ID: id, Status: status})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Sale{}, apperr.NotFound("Venta no encontrada.")
	}
	if err != nil {
		return domain.Sale{}, apperr.Internal(err)
	}
	return s.Get(ctx, id)
}

// GetCreditSettings devuelve la configuración de financiamiento.
func (s *Service) GetCreditSettings(ctx context.Context) (domain.CreditSettings, error) {
	row, err := s.store.Q.GetCreditSettings(ctx)
	if err != nil {
		return domain.CreditSettings{}, apperr.Internal(err)
	}
	return creditSettingsFromRow(row), nil
}

// UpdateCreditSettings reemplaza la configuración; solo debe invocarse desde admin.
func (s *Service) UpdateCreditSettings(ctx context.Context, in CreditSettingsInput, actorID uuid.UUID) (domain.CreditSettings, error) {
	if len(in.DownPaymentOptions) == 0 || len(in.DownPaymentOptions) > 10 {
		return domain.CreditSettings{}, validationField("down_payment_options", "Envía entre 1 y 10 anticipos.")
	}
	if len(in.CreditMonths) == 0 || len(in.CreditMonths) > 10 {
		return domain.CreditSettings{}, validationField("credit_months", "Envía entre 1 y 10 plazos.")
	}

	seenPercent := map[float64]struct{}{}
	percentages := make([]float64, 0, len(in.DownPaymentOptions))
	for _, value := range in.DownPaymentOptions {
		if value < 0 || value >= 100 {
			return domain.CreditSettings{}, validationField("down_payment_options", "Cada anticipo debe estar entre 0 y 99.99%.")
		}
		rounded := math.Round(value*100) / 100
		if _, exists := seenPercent[rounded]; exists {
			return domain.CreditSettings{}, validationField("down_payment_options", "No repitas anticipos.")
		}
		seenPercent[rounded] = struct{}{}
		percentages = append(percentages, rounded)
	}
	sort.Float64s(percentages)

	seenMonths := map[int32]struct{}{}
	months := make([]int32, 0, len(in.CreditMonths))
	for _, value := range in.CreditMonths {
		if value < 1 || value > 60 {
			return domain.CreditSettings{}, validationField("credit_months", "Cada plazo debe estar entre 1 y 60 meses.")
		}
		if _, exists := seenMonths[value]; exists {
			return domain.CreditSettings{}, validationField("credit_months", "No repitas plazos.")
		}
		seenMonths[value] = struct{}{}
		months = append(months, value)
	}
	sort.Slice(months, func(i, j int) bool { return months[i] < months[j] })

	if in.MonthlyInterestRate < 0 || in.MonthlyInterestRate > 100 {
		return domain.CreditSettings{}, validationField("monthly_interest_rate", "El interés mensual debe estar entre 0 y 100%.")
	}

	row, err := s.store.Q.UpdateCreditSettings(ctx, sqlc.UpdateCreditSettingsParams{
		DownPaymentOptions:  percentages,
		CreditMonths:        months,
		MonthlyInterestRate: math.Round(in.MonthlyInterestRate*100) / 100,
		UpdatedBy:           &actorID,
	})
	if err != nil {
		return domain.CreditSettings{}, apperr.Internal(err)
	}
	return creditSettingsFromRow(row), nil
}

func buildCreditPlan(total, downPercent float64, months int32, rate float64, saleDate time.Time) creditPlan {
	total = roundMoney(total)
	down := roundMoney(total * downPercent / 100)
	financed := roundMoney(total - down)
	interest := roundMoney(financed * rate / 100 * float64(months))
	remaining := roundMoney(total + interest - down)
	base := math.Floor((remaining/float64(months))*100) / 100
	base = roundMoney(base)

	payments := make([]domain.SalePayment, 0, int(months)+1)
	payments = append(payments, domain.SalePayment{
		InstallmentNumber: 0,
		Kind:              "anticipo",
		DueDate:           saleDate,
		Amount:            down,
	})
	for i := int32(1); i <= months; i++ {
		amount := base
		if i == months {
			amount = roundMoney(remaining - base*float64(months-1))
		}
		payments = append(payments, domain.SalePayment{
			InstallmentNumber: i,
			Kind:              "mensualidad",
			DueDate:           saleDate.AddDate(0, int(i), 0),
			Amount:            amount,
		})
	}

	return creditPlan{
		DownPaymentPercent:  downPercent,
		DownPayment:         down,
		FinancedAmount:      financed,
		MonthlyInterestRate: rate,
		Months:              months,
		TotalInterest:       interest,
		Payments:            payments,
	}
}

func saleFromGetRow(row sqlc.GetSaleByIDRow) domain.Sale {
	return domain.Sale{
		ID:                  row.ID,
		SaleNumber:          row.SaleNumber,
		ClientID:            row.ClientID,
		ClientName:          row.ClientName,
		ClientPhone:         row.ClientPhone,
		ClientEmail:         row.ClientEmail,
		SellerID:            row.SellerID,
		SellerName:          row.SellerName,
		SaleDate:            row.SaleDate.Time,
		Status:              row.Status,
		PaymentType:         row.PaymentType,
		DownPaymentPercent:  row.DownPaymentPercent,
		DownPayment:         row.DownPayment,
		FinancedAmount:      row.FinancedAmount,
		MonthlyInterestRate: row.MonthlyInterestRate,
		Months:              row.Months,
		TotalInterest:       row.TotalInterest,
		Total:               row.Total,
		CreatedAt:           row.CreatedAt,
		UpdatedAt:           row.UpdatedAt,
	}
}

func saleFromListRow(row sqlc.ListSalesRow) domain.Sale {
	return domain.Sale{
		ID:                  row.ID,
		SaleNumber:          row.SaleNumber,
		ClientID:            row.ClientID,
		ClientName:          row.ClientName,
		ClientPhone:         row.ClientPhone,
		ClientEmail:         row.ClientEmail,
		SellerID:            row.SellerID,
		SellerName:          row.SellerName,
		SaleDate:            row.SaleDate.Time,
		Status:              row.Status,
		PaymentType:         row.PaymentType,
		DownPaymentPercent:  row.DownPaymentPercent,
		DownPayment:         row.DownPayment,
		FinancedAmount:      row.FinancedAmount,
		MonthlyInterestRate: row.MonthlyInterestRate,
		Months:              row.Months,
		TotalInterest:       row.TotalInterest,
		Total:               row.Total,
		CreatedAt:           row.CreatedAt,
		UpdatedAt:           row.UpdatedAt,
	}
}

func creditSettingsFromRow(row sqlc.CreditSetting) domain.CreditSettings {
	return domain.CreditSettings{
		DownPaymentOptions:  row.DownPaymentOptions,
		CreditMonths:        row.CreditMonths,
		MonthlyInterestRate: row.MonthlyInterestRate,
		UpdatedAt:           row.UpdatedAt,
	}
}

func validStatus(value string) bool {
	return value == StatusQuote || value == StatusSale || value == StatusCanceled
}

func dateOnly(value time.Time) time.Time {
	return time.Date(value.Year(), value.Month(), value.Day(), 0, 0, 0, 0, time.UTC)
}

func roundMoney(value float64) float64 {
	return math.Round(value*100) / 100
}

func numericToFloat(value pgtype.Numeric) float64 {
	if !value.Valid {
		return 0
	}
	result, err := value.Float64Value()
	if err != nil || !result.Valid {
		return 0
	}
	return result.Float64
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
