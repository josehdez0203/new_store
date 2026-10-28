package server

import (
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/jhc/credit-store/server/internal/apperr"
	"github.com/jhc/credit-store/server/internal/domain"
	"github.com/jhc/credit-store/server/internal/sales"
)

type saleItemRequest struct {
	ProductID string `json:"product_id" binding:"required,uuid"`
	Quantity  int32  `json:"quantity" binding:"required,gt=0,lte=100000"`
}

type createSaleRequest struct {
	ClientID           string            `json:"client_id" binding:"required,uuid"`
	SellerID           string            `json:"seller_id" binding:"omitempty,uuid"`
	SaleDate           string            `json:"sale_date" binding:"omitempty"`
	Status             string            `json:"status" binding:"required,oneof=cotizacion venta"`
	PaymentType        string            `json:"payment_type" binding:"required,oneof=contado credito"`
	DownPaymentPercent float64           `json:"down_payment_percent" binding:"gte=0,lte=100"`
	Months             int32             `json:"months" binding:"gte=0,lte=60"`
	Items              []saleItemRequest `json:"items" binding:"required,min=1,max=50,dive"`
}

type updateSaleStatusRequest struct {
	Status string `json:"status" binding:"required,oneof=cotizacion venta"`
}

type updateCreditSettingsRequest struct {
	DownPaymentOptions  []float64 `json:"down_payment_options" binding:"required,min=1,max=10"`
	CreditMonths        []int32   `json:"credit_months" binding:"required,min=1,max=10"`
	MonthlyInterestRate float64   `json:"monthly_interest_rate" binding:"gte=0,lte=100"`
}

func (a *API) listSales(c *gin.Context) {
	authCtx, ok := a.requireAuth(c)
	if !ok {
		return
	}
	page, pageSize, ok := a.pagination(c)
	if !ok {
		return
	}

	filter := sales.ListFilter{
		Search:   c.Query("search"),
		Status:   c.Query("status"),
		Page:     page,
		PageSize: pageSize,
	}
	if !authCtx.User.HasRole("admin") {
		filter.SellerID = &authCtx.User.ID
	}

	items, total, err := a.services.Sales.List(c.Request.Context(), filter)
	if err != nil {
		a.fail(c, err)
		return
	}
	respondList(c, salesToResponse(items), pageMeta{
		Page:       page,
		PageSize:   pageSize,
		Total:      total,
		TotalPages: totalPages(total, pageSize),
	})
}

func (a *API) getSale(c *gin.Context) {
	authCtx, ok := a.requireAuth(c)
	if !ok {
		return
	}
	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}
	sale, err := a.services.Sales.Get(c.Request.Context(), id)
	if err != nil {
		a.fail(c, err)
		return
	}
	if !canAccessSale(authCtx.User, sale) {
		a.fail(c, apperr.NotFound("Venta no encontrada."))
		return
	}
	respond(c, http.StatusOK, saleToResponse(sale))
}

func (a *API) createSale(c *gin.Context) {
	authCtx, ok := a.requireAuth(c)
	if !ok {
		return
	}
	var req createSaleRequest
	if !a.bindJSON(c, &req) {
		return
	}

	clientID, err := uuid.Parse(req.ClientID)
	if err != nil {
		a.fail(c, apperr.Validation("Datos inválidos.", []apperr.FieldError{{Field: "client_id", Message: "Cliente inválido."}}))
		return
	}

	sellerID := authCtx.User.ID
	if authCtx.User.HasRole("admin") {
		if strings.TrimSpace(req.SellerID) == "" {
			a.fail(c, apperr.Validation("Datos inválidos.", []apperr.FieldError{{Field: "seller_id", Message: "Selecciona un vendedor."}}))
			return
		}
		sellerID, err = uuid.Parse(req.SellerID)
		if err != nil {
			a.fail(c, apperr.Validation("Datos inválidos.", []apperr.FieldError{{Field: "seller_id", Message: "Vendedor inválido."}}))
			return
		}
	}

	saleDate := time.Time{}
	if strings.TrimSpace(req.SaleDate) != "" {
		saleDate, err = time.Parse("2006-01-02", req.SaleDate)
		if err != nil {
			a.fail(c, apperr.Validation("Datos inválidos.", []apperr.FieldError{{Field: "sale_date", Message: "La fecha debe tener formato AAAA-MM-DD."}}))
			return
		}
	}

	items := make([]sales.ItemInput, 0, len(req.Items))
	for _, item := range req.Items {
		productID, err := uuid.Parse(item.ProductID)
		if err != nil {
			a.fail(c, apperr.Validation("Datos inválidos.", []apperr.FieldError{{Field: "items", Message: "Producto inválido."}}))
			return
		}
		items = append(items, sales.ItemInput{ProductID: productID, Quantity: item.Quantity})
	}

	sale, err := a.services.Sales.Create(c.Request.Context(), sales.CreateInput{
		ClientID:           clientID,
		SellerID:           sellerID,
		SaleDate:           saleDate,
		Status:             req.Status,
		PaymentType:        req.PaymentType,
		DownPaymentPercent: req.DownPaymentPercent,
		Months:             req.Months,
		Items:              items,
	})
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusCreated, saleToResponse(sale))
}

func (a *API) updateSaleStatus(c *gin.Context) {
	authCtx, ok := a.requireAuth(c)
	if !ok {
		return
	}
	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}
	var req updateSaleStatusRequest
	if !a.bindJSON(c, &req) {
		return
	}
	sale, err := a.services.Sales.Get(c.Request.Context(), id)
	if err != nil {
		a.fail(c, err)
		return
	}
	if !canAccessSale(authCtx.User, sale) {
		a.fail(c, apperr.NotFound("Venta no encontrada."))
		return
	}
	updated, err := a.services.Sales.UpdateStatus(c.Request.Context(), id, req.Status)
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, saleToResponse(updated))
}

func (a *API) cancelSale(c *gin.Context) {
	authCtx, ok := a.requireAuth(c)
	if !ok {
		return
	}
	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}
	sale, err := a.services.Sales.Get(c.Request.Context(), id)
	if err != nil {
		a.fail(c, err)
		return
	}
	if !canAccessSale(authCtx.User, sale) {
		a.fail(c, apperr.NotFound("Venta no encontrada."))
		return
	}
	updated, err := a.services.Sales.UpdateStatus(c.Request.Context(), id, sales.StatusCanceled)
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, saleToResponse(updated))
}

func (a *API) getCreditSettings(c *gin.Context) {
	settings, err := a.services.Sales.GetCreditSettings(c.Request.Context())
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, creditSettingsToResponse(settings))
}

func (a *API) updateCreditSettings(c *gin.Context) {
	authCtx, ok := a.requireAuth(c)
	if !ok {
		return
	}
	var req updateCreditSettingsRequest
	if !a.bindJSON(c, &req) {
		return
	}
	settings, err := a.services.Sales.UpdateCreditSettings(c.Request.Context(), sales.CreditSettingsInput{
		DownPaymentOptions:  req.DownPaymentOptions,
		CreditMonths:        req.CreditMonths,
		MonthlyInterestRate: req.MonthlyInterestRate,
	}, authCtx.User.ID)
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, creditSettingsToResponse(settings))
}

func canAccessSale(user domain.User, sale domain.Sale) bool {
	return user.HasRole("admin") || sale.SellerID == user.ID
}

func (a *API) updateSale(c *gin.Context) {
	authCtx, ok := a.requireAuth(c)
	if !ok {
		return
	}
	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}
	var req createSaleRequest
	if !a.bindJSON(c, &req) {
		return
	}

	existing, err := a.services.Sales.Get(c.Request.Context(), id)
	if err != nil {
		a.fail(c, err)
		return
	}
	if !canAccessSale(authCtx.User, existing) {
		a.fail(c, apperr.NotFound("Venta no encontrada."))
		return
	}

	clientID, err := uuid.Parse(req.ClientID)
	if err != nil {
		a.fail(c, apperr.Validation("Datos inválidos.", []apperr.FieldError{{Field: "client_id", Message: "Cliente inválido."}}))
		return
	}

	sellerID := authCtx.User.ID
	if authCtx.User.HasRole("admin") {
		if strings.TrimSpace(req.SellerID) == "" {
			a.fail(c, apperr.Validation("Datos inválidos.", []apperr.FieldError{{Field: "seller_id", Message: "Selecciona un vendedor."}}))
			return
		}
		sellerID, err = uuid.Parse(req.SellerID)
		if err != nil {
			a.fail(c, apperr.Validation("Datos inválidos.", []apperr.FieldError{{Field: "seller_id", Message: "Vendedor inválido."}}))
			return
		}
	}

	saleDate := time.Time{}
	if strings.TrimSpace(req.SaleDate) != "" {
		saleDate, err = time.Parse("2006-01-02", req.SaleDate)
		if err != nil {
			a.fail(c, apperr.Validation("Datos inválidos.", []apperr.FieldError{{Field: "sale_date", Message: "La fecha debe tener formato AAAA-MM-DD."}}))
			return
		}
	}

	items := make([]sales.ItemInput, 0, len(req.Items))
	for _, item := range req.Items {
		productID, err := uuid.Parse(item.ProductID)
		if err != nil {
			a.fail(c, apperr.Validation("Datos inválidos.", []apperr.FieldError{{Field: "items", Message: "Producto inválido."}}))
			return
		}
		items = append(items, sales.ItemInput{ProductID: productID, Quantity: item.Quantity})
	}

	sale, err := a.services.Sales.Update(c.Request.Context(), id, sales.CreateInput{
		ClientID:           clientID,
		SellerID:           sellerID,
		SaleDate:           saleDate,
		Status:             req.Status,
		PaymentType:        req.PaymentType,
		DownPaymentPercent: req.DownPaymentPercent,
		Months:             req.Months,
		Items:              items,
	})
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, saleToResponse(sale))
}
