package server

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/jhc/credit-store/server/internal/customers"
)

type customerRequest struct {
	Name       string `json:"name" binding:"required,min=2,max=150"`
	Address    string `json:"address" binding:"omitempty,max=500"`
	City       string `json:"city" binding:"omitempty,max=120"`
	PostalCode string `json:"postal_code" binding:"omitempty,max=20"`
	Phone      string `json:"phone" binding:"omitempty,max=30"`
	Email      string `json:"email" binding:"omitempty,email,max=254"`
	Status     string `json:"status" binding:"required,oneof=prospecto cliente en_pago liquidado"`
}

func (a *API) listCustomers(c *gin.Context) {
	page, pageSize, ok := a.pagination(c)
	if !ok {
		return
	}

	items, total, err := a.services.Customers.List(c.Request.Context(), customers.ListFilter{
		Search:   c.Query("search"),
		Status:   c.Query("status"),
		Page:     page,
		PageSize: pageSize,
	})
	if err != nil {
		a.fail(c, err)
		return
	}

	respondList(c, customersToResponse(items), pageMeta{
		Page:       page,
		PageSize:   pageSize,
		Total:      total,
		TotalPages: totalPages(total, pageSize),
	})
}

func (a *API) getCustomer(c *gin.Context) {
	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}

	customer, err := a.services.Customers.Get(c.Request.Context(), id)
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, customerToResponse(customer))
}

func (a *API) createCustomer(c *gin.Context) {
	var req customerRequest
	if !a.bindJSON(c, &req) {
		return
	}

	customer, err := a.services.Customers.Create(c.Request.Context(), customers.Input{
		Name:       req.Name,
		Address:    req.Address,
		City:       req.City,
		PostalCode: req.PostalCode,
		Phone:      req.Phone,
		Email:      req.Email,
		Status:     req.Status,
	})
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusCreated, customerToResponse(customer))
}

func (a *API) updateCustomer(c *gin.Context) {
	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}

	var req customerRequest
	if !a.bindJSON(c, &req) {
		return
	}

	customer, err := a.services.Customers.Update(c.Request.Context(), id, customers.Input{
		Name:       req.Name,
		Address:    req.Address,
		City:       req.City,
		PostalCode: req.PostalCode,
		Phone:      req.Phone,
		Email:      req.Email,
		Status:     req.Status,
	})
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, customerToResponse(customer))
}

func (a *API) deleteCustomer(c *gin.Context) {
	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}

	if err := a.services.Customers.Delete(c.Request.Context(), id); err != nil {
		a.fail(c, err)
		return
	}
	noContent(c)
}
