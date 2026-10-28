package server

import (
	"errors"
	"fmt"
	"io"
	"net/http"
	"reflect"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"

	"github.com/jhc/credit-store/server/internal/apperr"
)

type pageMeta struct {
	Page       int   `json:"page"`
	PageSize   int   `json:"page_size"`
	Total      int64 `json:"total"`
	TotalPages int   `json:"total_pages"`
}

type errorBody struct {
	Code    string              `json:"code"`
	Message string              `json:"message"`
	Details []apperr.FieldError `json:"details,omitempty"`
}

type errorResponse struct {
	Error errorBody `json:"error"`
}

func respond(c *gin.Context, status int, data any) {
	c.JSON(status, gin.H{"data": data})
}

func respondList(c *gin.Context, data any, meta any) {
	c.JSON(http.StatusOK, gin.H{"data": data, "meta": meta})
}

func (a *API) fail(c *gin.Context, err error) {
	if err == nil {
		err = apperr.Internal(nil)
	}

	var appErr *apperr.Error
	if !errors.As(err, &appErr) {
		appErr = apperr.Internal(err)
	}

	if appErr.Status >= http.StatusInternalServerError {
		a.log.Error("request failed",
			"error", err,
			"path", c.Request.URL.Path,
			"method", c.Request.Method,
			"request_id", requestIDFrom(c),
		)
	}

	message := appErr.Message
	if message == "" {
		message = http.StatusText(appErr.Status)
	}
	body := errorBody{
		Code:    appErr.Code,
		Message: message,
		Details: appErr.Details,
	}
	c.AbortWithStatusJSON(appErr.Status, errorResponse{Error: body})
}

func (a *API) bindJSON(c *gin.Context, dst any) bool {
	return a.bind(c, dst, true)
}

func (a *API) bindForm(c *gin.Context, dst any) bool {
	return a.bind(c, dst, false)
}

func (a *API) bind(c *gin.Context, dst any, jsonBody bool) bool {
	var err error
	if jsonBody {
		err = c.ShouldBindJSON(dst)
	} else {
		err = c.ShouldBind(dst)
	}
	if err == nil {
		return true
	}

	var validationErrors validator.ValidationErrors
	if errors.As(err, &validationErrors) {
		a.fail(c, apperr.Validation("Revisa los datos enviados.", validationDetails(validationErrors, dst)))
		return false
	}

	if jsonBody {
		if errors.Is(err, io.EOF) {
			a.fail(c, apperr.Validation("El cuerpo de la solicitud es obligatorio.", nil))
			return false
		}
		a.fail(c, apperr.Validation("El cuerpo de la solicitud no es un JSON válido.", nil))
		return false
	}

	a.fail(c, apperr.Validation("El formulario de la solicitud no es válido.", nil))
	return false
}

func validationDetails(fieldErrors validator.ValidationErrors, payload any) []apperr.FieldError {
	structType := reflect.TypeOf(payload)
	for structType != nil && structType.Kind() == reflect.Pointer {
		structType = structType.Elem()
	}

	details := make([]apperr.FieldError, 0, len(fieldErrors))
	for _, fieldError := range fieldErrors {
		field := fieldError.StructField()
		if field == "" {
			field = fieldError.Field()
		}
		if structType != nil && structType.Kind() == reflect.Struct {
			if structField, ok := structType.FieldByName(fieldError.StructField()); ok {
				jsonTag := structField.Tag.Get("json")
				if index := strings.IndexByte(jsonTag, ','); index >= 0 {
					jsonTag = jsonTag[:index]
				}
				if jsonTag != "" && jsonTag != "-" {
					field = jsonTag
				}
			}
		}
		details = append(details, apperr.FieldError{
			Field:   field,
			Message: validationMessage(fieldError),
		})
	}
	return details
}

func validationMessage(fieldError validator.FieldError) string {
	switch fieldError.Tag() {
	case "required":
		return "Este campo es obligatorio."
	case "email":
		return "Ingresa un correo electrónico válido."
	case "min":
		if fieldError.Kind() == reflect.String {
			return fmt.Sprintf("Debe tener al menos %s caracteres.", fieldError.Param())
		}
		return fmt.Sprintf("Debe ser mayor o igual a %s.", fieldError.Param())
	case "max":
		if fieldError.Kind() == reflect.String {
			return fmt.Sprintf("Debe tener como máximo %s caracteres.", fieldError.Param())
		}
		return fmt.Sprintf("Debe ser menor o igual a %s.", fieldError.Param())
	case "gte":
		return fmt.Sprintf("Debe ser mayor o igual a %s.", fieldError.Param())
	case "lte":
		return fmt.Sprintf("Debe ser menor o igual a %s.", fieldError.Param())
	case "uuid", "uuid4":
		return "El identificador no tiene un formato UUID válido."
	case "regexp":
		return "El formato del valor no es válido."
	case "oneof":
		return fmt.Sprintf("Debe ser uno de: %s.", fieldError.Param())
	case "url":
		return "Ingresa una URL válida."
	default:
		return "El valor no es válido."
	}
}
