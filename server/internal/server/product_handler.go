package server

import (
	"io"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"github.com/jhc/credit-store/server/internal/apperr"
	"github.com/jhc/credit-store/server/internal/products"
)

type productRequest struct {
	Name        string  `json:"name" form:"name" binding:"required,min=2,max=150"`
	Description string  `json:"description" form:"description" binding:"omitempty,max=2000"`
	Barcode     string  `json:"barcode" form:"barcode" binding:"omitempty,max=64"`
	Price       float64 `json:"price" form:"price" binding:"gte=0"`
	Cost        float64 `json:"cost" form:"cost" binding:"gte=0"`
	Type        string  `json:"type" form:"type" binding:"required,oneof=product service producto servicio"`
}

func (a *API) listProducts(c *gin.Context) {
	page, pageSize, ok := a.pagination(c)
	if !ok {
		return
	}

	items, total, err := a.services.Products.List(c.Request.Context(), products.ListFilter{
		Search:   c.Query("search"),
		Type:     c.Query("type"),
		Page:     page,
		PageSize: pageSize,
	})
	if err != nil {
		a.fail(c, err)
		return
	}

	respondList(c, productsToResponse(items, a.canViewMargin(c)), pageMeta{
		Page:       page,
		PageSize:   pageSize,
		Total:      total,
		TotalPages: totalPages(total, pageSize),
	})
}

func (a *API) getProduct(c *gin.Context) {
	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}

	product, err := a.services.Products.Get(c.Request.Context(), id)
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, productToResponse(product, a.canViewMargin(c)))
}

func (a *API) createProduct(c *gin.Context) {
	if c.ContentType() != "multipart/form-data" {
		a.fail(c, apperr.Validation(
			"Para crear un producto envía multipart/form-data con al menos 3 fotos.", nil))
		return
	}

	var req productRequest
	if !a.bindForm(c, &req) {
		return
	}

	images, err := a.parseImageUploads(c, "images", 3, products.MaxImagesPerProduct)
	if err != nil {
		a.fail(c, err)
		return
	}

	product, err := a.services.Products.CreateWithImages(c.Request.Context(), products.Input{
		Name:        req.Name,
		Description: &req.Description,
		Barcode:     &req.Barcode,
		Price:       req.Price,
		Cost:        req.Cost,
		Type:        req.Type,
	}, images)
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusCreated, productToResponse(product, a.canViewMargin(c)))
}

func (a *API) updateProduct(c *gin.Context) {
	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}

	var req productRequest
	if !a.bindJSON(c, &req) {
		return
	}

	product, err := a.services.Products.Update(c.Request.Context(), id, products.Input{
		Name:        req.Name,
		Description: &req.Description,
		Barcode:     &req.Barcode,
		Price:       req.Price,
		Cost:        req.Cost,
		Type:        req.Type,
	})
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, productToResponse(product, a.canViewMargin(c)))
}

func (a *API) deleteProduct(c *gin.Context) {
	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}

	if err := a.services.Products.Delete(c.Request.Context(), id); err != nil {
		a.fail(c, err)
		return
	}
	noContent(c)
}

func (a *API) listProductImages(c *gin.Context) {
	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}

	images, err := a.services.Products.ListImages(c.Request.Context(), id)
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, productImagesToResponse(images))
}

func (a *API) addProductImages(c *gin.Context) {
	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}

	images, err := a.parseImageUploads(c, "images", 1, products.MaxImagesPerProduct)
	if err != nil {
		a.fail(c, err)
		return
	}

	product, err := a.services.Products.AddImages(c.Request.Context(), id, images)
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, productToResponse(product, a.canViewMargin(c)))
}

func (a *API) replaceProductImage(c *gin.Context) {
	productID, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}
	imageID, ok := a.uuidParam(c, "image_id")
	if !ok {
		return
	}

	images, err := a.parseImageUploads(c, "image", 1, 1)
	if err != nil {
		a.fail(c, err)
		return
	}

	product, err := a.services.Products.ReplaceImage(c.Request.Context(), productID, imageID, images[0])
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, productToResponse(product, a.canViewMargin(c)))
}

func (a *API) deleteProductImage(c *gin.Context) {
	productID, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}
	imageID, ok := a.uuidParam(c, "image_id")
	if !ok {
		return
	}

	if err := a.services.Products.DeleteImage(c.Request.Context(), productID, imageID); err != nil {
		a.fail(c, err)
		return
	}
	noContent(c)
}

func (a *API) parseImageUploads(c *gin.Context, field string, min, max int) ([]products.ImageUpload, error) {
	if c.ContentType() != "multipart/form-data" {
		return nil, apperr.Validation("Envía las fotos como multipart/form-data.", nil)
	}

	form, err := c.MultipartForm()
	if err != nil {
		return nil, apperr.Validation("No se pudo leer el formulario de fotos.", nil)
	}

	headers := form.File[field]
	if len(headers) < min {
		if min >= 3 {
			return nil, apperr.Validation("Datos inválidos.",
				[]apperr.FieldError{{Field: "images", Message: "El producto debe tener al menos 3 fotos."}})
		}
		return nil, apperr.Validation("Datos inválidos.",
			[]apperr.FieldError{{Field: "images", Message: "Selecciona al menos una foto."}})
	}
	if len(headers) > max {
		message := "Puedes subir como máximo " + strconv.Itoa(max) + " fotos."
		if max == 1 {
			message = "Solo se permite una foto en este campo."
		}
		return nil, apperr.Validation("Datos inválidos.",
			[]apperr.FieldError{{Field: "images", Message: message}})
	}

	images := make([]products.ImageUpload, 0, len(headers))
	var total int64
	for _, header := range headers {
		if header.Size > products.MaxImageSize {
			return nil, apperr.Validation("Datos inválidos.",
				[]apperr.FieldError{{Field: "images", Message: "Cada foto debe pesar como máximo 5 MB."}})
		}

		file, err := header.Open()
		if err != nil {
			return nil, apperr.Validation("No se pudo leer una de las fotos.", nil)
		}
		data, readErr := io.ReadAll(io.LimitReader(file, products.MaxImageSize+1))
		_ = file.Close()
		if readErr != nil {
			return nil, apperr.Validation("No se pudo leer una de las fotos.", nil)
		}
		if int64(len(data)) > products.MaxImageSize {
			return nil, apperr.Validation("Datos inválidos.",
				[]apperr.FieldError{{Field: "images", Message: "Cada foto debe pesar como máximo 5 MB."}})
		}

		total += int64(len(data))
		if total > products.MaxTotalImagesBytes {
			return nil, apperr.Validation("Datos inválidos.",
				[]apperr.FieldError{{Field: "images", Message: "El lote de fotos supera el tamaño máximo permitido."}})
		}

		images = append(images, products.ImageUpload{
			OriginalName: header.Filename,
			MIME:         http.DetectContentType(data),
			Data:         data,
		})
	}
	return images, nil
}

func (a *API) canViewMargin(c *gin.Context) bool {
	authCtx := authContextFrom(c)
	return authCtx != nil && authCtx.HasPermission("products.view_margin")
}
