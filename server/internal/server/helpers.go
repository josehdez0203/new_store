package server

import (
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/jhc/credit-store/server/internal/apperr"
	"github.com/jhc/credit-store/server/internal/domain"
)

func (a *API) uuidParam(c *gin.Context, name string) (uuid.UUID, bool) {
	raw := strings.TrimSpace(c.Param(name))
	id, err := uuid.Parse(raw)
	if err != nil {
		a.fail(c, apperr.BadRequest("El identificador debe ser un UUID válido."))
		return uuid.Nil, false
	}
	return id, true
}

func (a *API) pagination(c *gin.Context) (int, int, bool) {
	page := 1
	pageSize := 10

	if raw := strings.TrimSpace(c.Query("page")); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed < 1 || parsed > 100000 {
			a.fail(c, apperr.BadRequest("El parámetro page debe ser un entero entre 1 y 100000."))
			return 0, 0, false
		}
		page = parsed
	}

	if raw := strings.TrimSpace(c.Query("page_size")); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed < 1 || parsed > 100 {
			a.fail(c, apperr.BadRequest("El parámetro page_size debe ser un entero entre 1 y 100."))
			return 0, 0, false
		}
		pageSize = parsed
	}

	return page, pageSize, true
}

func (a *API) optionalBoolQuery(c *gin.Context, name string) (*bool, bool) {
	raw := strings.TrimSpace(c.Query(name))
	if raw == "" {
		return nil, true
	}
	parsed, err := strconv.ParseBool(raw)
	if err != nil {
		a.fail(c, apperr.BadRequest(fmt.Sprintf("El parámetro %s debe ser true o false.", name)))
		return nil, false
	}
	return &parsed, true
}

func (a *API) requireAuth(c *gin.Context) (*domain.AuthContext, bool) {
	authCtx := authContextFrom(c)
	if authCtx == nil {
		a.fail(c, apperr.Unauthorized("Se requiere autenticación."))
		return nil, false
	}
	return authCtx, true
}

func parseUUIDList(field string, raw []string) ([]uuid.UUID, error) {
	ids := make([]uuid.UUID, 0, len(raw))
	for index, value := range raw {
		id, err := uuid.Parse(strings.TrimSpace(value))
		if err != nil {
			return nil, apperr.Validation("Datos inválidos.", []apperr.FieldError{{
				Field:   fmt.Sprintf("%s[%d]", field, index),
				Message: "El identificador no tiene un formato UUID válido.",
			}})
		}
		ids = append(ids, id)
	}
	return ids, nil
}

func totalPages(total int64, pageSize int) int {
	if total <= 0 || pageSize <= 0 {
		return 0
	}
	pages := total / int64(pageSize)
	if total%int64(pageSize) != 0 {
		pages++
	}
	return int(pages)
}

func noContent(c *gin.Context) {
	c.Status(http.StatusNoContent)
}
