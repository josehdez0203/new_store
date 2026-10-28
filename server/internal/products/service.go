// Package products implementa el CRUD del catálogo de productos y servicios,
// incluyendo la galería de fotos almacenada en DOWNLOADS_DIR.
package products

import (
	"context"
	"errors"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/jhc/credit-store/server/internal/apperr"
	"github.com/jhc/credit-store/server/internal/database"
	"github.com/jhc/credit-store/server/internal/database/sqlc"
	"github.com/jhc/credit-store/server/internal/domain"
)

const (
	// TypeProduct identifica un bien físico.
	TypeProduct = "product"
	// TypeService identifica un servicio intangible.
	TypeService = "service"

	// MaxImageSize es el tamaño máximo por fotografía (5 MB).
	MaxImageSize int64 = 5 << 20
	// MaxImagesPerProduct es el máximo de fotografías por producto.
	MaxImagesPerProduct = 20
	// MaxTotalImagesBytes limita el total de un lote de fotografías (60 MB).
	MaxTotalImagesBytes int64 = 60 << 20

	maxAmount = 9_999_999_999.99
)

var allowedImageTypes = map[string]string{
	"image/jpeg": ".jpg",
	"image/png":  ".png",
	"image/webp": ".webp",
}

// Service contiene la lógica del catálogo de productos.
type Service struct {
	store        *database.Store
	downloadsDir string
}

// NewService construye el servicio de productos.
func NewService(store *database.Store, downloadsDir string) *Service {
	return &Service{store: store, downloadsDir: downloadsDir}
}

// ListFilter son los filtros y la paginación del listado.
type ListFilter struct {
	Search   string
	Type     string
	Page     int
	PageSize int
}

// Input son los datos editables de un producto o servicio.
type Input struct {
	Name        string
	Description *string
	Barcode     *string
	Price       float64
	Cost        float64
	Type        string
}

// ImageUpload es una fotografía recibida desde multipart/form-data.
type ImageUpload struct {
	OriginalName string
	MIME         string
	Data         []byte
}

// List devuelve productos paginados y el total.
func (s *Service) List(ctx context.Context, filter ListFilter) ([]domain.Product, int64, error) {
	if filter.Page < 1 {
		filter.Page = 1
	}
	if filter.PageSize < 1 || filter.PageSize > 100 {
		filter.PageSize = 10
	}

	search := strings.TrimSpace(filter.Search)
	typeValue := strings.TrimSpace(filter.Type)
	if typeValue != "" {
		normalized, ok := normalizeType(typeValue)
		if !ok {
			return nil, 0, validationField("type", "El tipo debe ser product o service.")
		}
		typeValue = normalized
	}

	params := sqlc.ListProductsParams{
		Search: optionalString(search),
		Type:   optionalString(typeValue),
		Offset: int32((filter.Page - 1) * filter.PageSize),
		Limit:  int32(filter.PageSize),
	}

	rows, err := s.store.Q.ListProducts(ctx, params)
	if err != nil {
		return nil, 0, apperr.Internal(err)
	}

	total, err := s.store.Q.CountProducts(ctx, sqlc.CountProductsParams{
		Search: params.Search,
		Type:   params.Type,
	})
	if err != nil {
		return nil, 0, apperr.Internal(err)
	}

	items := make([]domain.Product, 0, len(rows))
	for _, row := range rows {
		product := productFromModel(row)
		if err := s.attachImages(ctx, &product); err != nil {
			return nil, 0, err
		}
		items = append(items, product)
	}
	return items, total, nil
}

// Get devuelve un producto por ID con su galería.
func (s *Service) Get(ctx context.Context, id uuid.UUID) (domain.Product, error) {
	row, err := s.store.Q.GetProductByID(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Product{}, apperr.NotFound("Producto no encontrado.")
	}
	if err != nil {
		return domain.Product{}, apperr.Internal(err)
	}

	product := productFromModel(row)
	if err := s.attachImages(ctx, &product); err != nil {
		return domain.Product{}, err
	}
	return product, nil
}

// CreateWithImages registra un producto y sus fotografías.
func (s *Service) CreateWithImages(ctx context.Context, in Input, images []ImageUpload) (domain.Product, error) {
	prepared, err := prepareInput(in)
	if err != nil {
		return domain.Product{}, err
	}
	if err := validateImages(images, 3); err != nil {
		return domain.Product{}, err
	}
	if err := s.ensureBarcodeAvailable(ctx, prepared.Barcode, uuid.Nil); err != nil {
		return domain.Product{}, err
	}

	var productID uuid.UUID
	saved := make([]string, 0, len(images))
	err = s.store.WithTx(ctx, func(q *sqlc.Queries) error {
		row, err := q.CreateProduct(ctx, sqlc.CreateProductParams{
			Name:        prepared.Name,
			Description: prepared.Description,
			Barcode:     prepared.Barcode,
			Price:       prepared.Price,
			Cost:        prepared.Cost,
			Type:        prepared.Type,
		})
		if err != nil {
			return err
		}
		productID = row.ID
		for i := range images {
			fullPath, err := s.storeImage(ctx, q, row.ID, images[i], int32(i))
			if err != nil {
				return err
			}
			saved = append(saved, fullPath)
		}
		return nil
	})
	if err != nil {
		removeFiles(saved)
		if productID != uuid.Nil {
			_ = os.Remove(s.productDir(productID))
		}
		if apperr.IsUniqueViolation(err) {
			return domain.Product{}, apperr.Conflict("Ya existe un producto con ese código de barras.")
		}
		return domain.Product{}, apperr.Internal(err)
	}

	return s.Get(ctx, productID)
}

// Update reemplaza los datos editables de un producto. Las fotos se gestionan
// en endpoints separados.
func (s *Service) Update(ctx context.Context, id uuid.UUID, in Input) (domain.Product, error) {
	if _, err := s.store.Q.GetProductByID(ctx, id); errors.Is(err, pgx.ErrNoRows) {
		return domain.Product{}, apperr.NotFound("Producto no encontrado.")
	} else if err != nil {
		return domain.Product{}, apperr.Internal(err)
	}

	prepared, err := prepareInput(in)
	if err != nil {
		return domain.Product{}, err
	}

	if err := s.ensureBarcodeAvailable(ctx, prepared.Barcode, id); err != nil {
		return domain.Product{}, err
	}

	row, err := s.store.Q.UpdateProduct(ctx, sqlc.UpdateProductParams{
		ID:          id,
		Name:        prepared.Name,
		Description: prepared.Description,
		Barcode:     prepared.Barcode,
		Price:       prepared.Price,
		Cost:        prepared.Cost,
		Type:        prepared.Type,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Product{}, apperr.NotFound("Producto no encontrado.")
	}
	if err != nil {
		if apperr.IsUniqueViolation(err) {
			return domain.Product{}, apperr.Conflict("Ya existe un producto con ese código de barras.")
		}
		return domain.Product{}, apperr.Internal(err)
	}

	product := productFromModel(row)
	if err := s.attachImages(ctx, &product); err != nil {
		return domain.Product{}, err
	}
	return product, nil
}

// Delete aplica soft delete al producto. La galería se conserva para futuras
// consultas históricas.
func (s *Service) Delete(ctx context.Context, id uuid.UUID) error {
	affected, err := s.store.Q.SoftDeleteProduct(ctx, id)
	if err != nil {
		return apperr.Internal(err)
	}
	if affected == 0 {
		return apperr.NotFound("Producto no encontrado.")
	}
	return nil
}

// ListImages devuelve la galería de un producto.
func (s *Service) ListImages(ctx context.Context, productID uuid.UUID) ([]domain.ProductImage, error) {
	if _, err := s.store.Q.GetProductByID(ctx, productID); errors.Is(err, pgx.ErrNoRows) {
		return nil, apperr.NotFound("Producto no encontrado.")
	} else if err != nil {
		return nil, apperr.Internal(err)
	}
	return s.loadImages(ctx, productID)
}

// AddImages agrega una o más fotos al producto.
func (s *Service) AddImages(ctx context.Context, productID uuid.UUID, images []ImageUpload) (domain.Product, error) {
	if _, err := s.store.Q.GetProductByID(ctx, productID); errors.Is(err, pgx.ErrNoRows) {
		return domain.Product{}, apperr.NotFound("Producto no encontrado.")
	} else if err != nil {
		return domain.Product{}, apperr.Internal(err)
	}

	if err := validateImages(images, 1); err != nil {
		return domain.Product{}, err
	}

	count, err := s.store.Q.CountProductImages(ctx, productID)
	if err != nil {
		return domain.Product{}, apperr.Internal(err)
	}
	if count+int64(len(images)) > int64(MaxImagesPerProduct) {
		return domain.Product{}, validationField("images",
			"El producto no puede superar las 20 fotografías.")
	}

	saved := make([]string, 0, len(images))
	err = s.store.WithTx(ctx, func(q *sqlc.Queries) error {
		next, err := q.NextProductImageSortOrder(ctx, productID)
		if err != nil {
			return err
		}
		for i := range images {
			fullPath, err := s.storeImage(ctx, q, productID, images[i], next+int32(i))
			if err != nil {
				return err
			}
			saved = append(saved, fullPath)
		}
		return nil
	})
	if err != nil {
		removeFiles(saved)
		return domain.Product{}, apperr.Internal(err)
	}

	return s.Get(ctx, productID)
}

// ReplaceImage cambia el archivo de una fotografía conservando su posición.
func (s *Service) ReplaceImage(ctx context.Context, productID, imageID uuid.UUID, image ImageUpload) (domain.Product, error) {
	previous, err := s.store.Q.GetProductImageByID(ctx, sqlc.GetProductImageByIDParams{
		ID:        imageID,
		ProductID: productID,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Product{}, apperr.NotFound("Foto no encontrada.")
	}
	if err != nil {
		return domain.Product{}, apperr.Internal(err)
	}

	uploads := []ImageUpload{image}
	if err := validateImages(uploads, 1); err != nil {
		return domain.Product{}, err
	}
	image = uploads[0]

	fileName, relPath, fullPath, err := s.writeImage(productID, image)
	if err != nil {
		return domain.Product{}, err
	}

	_, err = s.store.Q.UpdateProductImage(ctx, sqlc.UpdateProductImageParams{
		ID:           imageID,
		ProductID:    productID,
		FileName:     fileName,
		FilePath:     relPath,
		OriginalName: originalName(image.OriginalName),
		MimeType:     image.MIME,
		SizeBytes:    int64(len(image.Data)),
	})
	if errors.Is(err, pgx.ErrNoRows) {
		_ = os.Remove(fullPath)
		return domain.Product{}, apperr.NotFound("Foto no encontrada.")
	}
	if err != nil {
		_ = os.Remove(fullPath)
		return domain.Product{}, apperr.Internal(err)
	}

	_ = os.Remove(s.diskPath(previous.FilePath))
	return s.Get(ctx, productID)
}

// DeleteImage elimina una fotografía, sin permitir bajar de tres.
func (s *Service) DeleteImage(ctx context.Context, productID, imageID uuid.UUID) error {
	image, err := s.store.Q.GetProductImageByID(ctx, sqlc.GetProductImageByIDParams{
		ID:        imageID,
		ProductID: productID,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return apperr.NotFound("Foto no encontrada.")
	}
	if err != nil {
		return apperr.Internal(err)
	}

	count, err := s.store.Q.CountProductImages(ctx, productID)
	if err != nil {
		return apperr.Internal(err)
	}
	if count <= 3 {
		return apperr.Conflict("El producto debe conservar al menos 3 fotos.")
	}

	affected, err := s.store.Q.DeleteProductImage(ctx, sqlc.DeleteProductImageParams{
		ID:        imageID,
		ProductID: productID,
	})
	if err != nil {
		return apperr.Internal(err)
	}
	if affected == 0 {
		return apperr.NotFound("Foto no encontrada.")
	}

	_ = os.Remove(s.diskPath(image.FilePath))
	return nil
}

func (s *Service) attachImages(ctx context.Context, product *domain.Product) error {
	images, err := s.loadImages(ctx, product.ID)
	if err != nil {
		return err
	}
	product.Images = images
	return nil
}

func (s *Service) loadImages(ctx context.Context, productID uuid.UUID) ([]domain.ProductImage, error) {
	rows, err := s.store.Q.ListProductImages(ctx, productID)
	if err != nil {
		return nil, apperr.Internal(err)
	}
	images := make([]domain.ProductImage, 0, len(rows))
	for _, row := range rows {
		images = append(images, imageFromModel(row))
	}
	return images, nil
}

func (s *Service) storeImage(ctx context.Context, q *sqlc.Queries, productID uuid.UUID, image ImageUpload, sortOrder int32) (string, error) {
	fileName, relPath, fullPath, err := s.writeImage(productID, image)
	if err != nil {
		return "", err
	}

	_, err = q.CreateProductImage(ctx, sqlc.CreateProductImageParams{
		ProductID:    productID,
		FileName:     fileName,
		FilePath:     relPath,
		OriginalName: originalName(image.OriginalName),
		MimeType:     image.MIME,
		SizeBytes:    int64(len(image.Data)),
		SortOrder:    sortOrder,
	})
	if err != nil {
		_ = os.Remove(fullPath)
		return "", err
	}
	return fullPath, nil
}

func (s *Service) writeImage(productID uuid.UUID, image ImageUpload) (string, string, string, error) {
	ext, ok := allowedImageTypes[image.MIME]
	if !ok {
		return "", "", "", validationField("images", "El formato de la foto no es válido. Usa JPG, PNG o WebP.")
	}

	dir := s.productDir(productID)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", "", "", apperr.Internal(err)
	}

	fileName := uuid.NewString() + ext
	fullPath := filepath.Join(dir, fileName)
	if err := os.WriteFile(fullPath, image.Data, 0o644); err != nil {
		return "", "", "", apperr.Internal(err)
	}

	relPath := filepath.ToSlash(filepath.Join("products", productID.String(), fileName))
	return fileName, relPath, fullPath, nil
}

func (s *Service) productDir(productID uuid.UUID) string {
	return filepath.Join(s.downloadsDir, "products", productID.String())
}

func (s *Service) diskPath(relPath string) string {
	return filepath.Join(s.downloadsDir, filepath.FromSlash(relPath))
}

func (s *Service) ensureBarcodeAvailable(ctx context.Context, barcode *string, excludeID uuid.UUID) error {
	if barcode == nil {
		return nil
	}
	exists, err := s.store.Q.BarcodeExists(ctx, sqlc.BarcodeExistsParams{
		Barcode: barcode,
		ID:      excludeID,
	})
	if err != nil {
		return apperr.Internal(err)
	}
	if exists {
		return apperr.Conflict("Ya existe un producto con ese código de barras.")
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

	description := normalizeOptional(in.Description)
	if description != nil && len(*description) > 2000 {
		return Input{}, validationField("description", "La descripción no puede superar 2000 caracteres.")
	}

	barcode := normalizeOptional(in.Barcode)
	if barcode != nil && len(*barcode) > 64 {
		return Input{}, validationField("barcode", "El código de barras no puede superar 64 caracteres.")
	}

	if math.IsNaN(in.Price) || math.IsInf(in.Price, 0) || in.Price < 0 || in.Price > maxAmount {
		return Input{}, validationField("price", "El precio debe ser un monto válido mayor o igual a 0.")
	}
	if math.IsNaN(in.Cost) || math.IsInf(in.Cost, 0) || in.Cost < 0 || in.Cost > maxAmount {
		return Input{}, validationField("cost", "El costo debe ser un monto válido mayor o igual a 0.")
	}
	typeValue, ok := normalizeType(in.Type)
	if !ok {
		return Input{}, validationField("type", "El tipo debe ser product o service.")
	}

	return Input{
		Name:        name,
		Description: description,
		Barcode:     barcode,
		Price:       round2(in.Price),
		Cost:        round2(in.Cost),
		Type:        typeValue,
	}, nil
}

func validateImages(images []ImageUpload, min int) error {
	if len(images) < min {
		if min >= 3 {
			return validationField("images", "El producto debe tener al menos 3 fotos.")
		}
		return validationField("images", "Selecciona al menos una foto.")
	}
	if len(images) > MaxImagesPerProduct {
		return validationField("images", "Puedes subir como máximo 20 fotos por producto.")
	}

	var total int64
	for i := range images {
		if len(images[i].Data) == 0 {
			return validationField("images", "Una de las fotos está vacía.")
		}
		if int64(len(images[i].Data)) > MaxImageSize {
			return validationField("images", "Cada foto debe pesar como máximo 5 MB.")
		}

		mime := strings.ToLower(strings.TrimSpace(images[i].MIME))
		if mime == "" {
			mime = http.DetectContentType(images[i].Data)
		}
		if _, ok := allowedImageTypes[mime]; !ok {
			return validationField("images", "El formato de la foto no es válido. Usa JPG, PNG o WebP.")
		}
		images[i].MIME = mime

		total += int64(len(images[i].Data))
		if total > MaxTotalImagesBytes {
			return validationField("images", "El lote de fotos supera el tamaño máximo permitido.")
		}
	}
	return nil
}

func normalizeType(value string) (string, bool) {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case TypeProduct, "producto":
		return TypeProduct, true
	case TypeService, "servicio":
		return TypeService, true
	default:
		return "", false
	}
}

func normalizeOptional(value *string) *string {
	if value == nil {
		return nil
	}
	trimmed := strings.TrimSpace(*value)
	if trimmed == "" {
		return nil
	}
	return &trimmed
}

func optionalString(value string) *string {
	if value == "" {
		return nil
	}
	return &value
}

func originalName(value string) *string {
	value = strings.TrimSpace(filepath.Base(value))
	if value == "" || value == "." {
		return nil
	}
	if len(value) > 255 {
		value = value[:255]
	}
	return &value
}

func round2(value float64) float64 {
	return math.Round(value*100) / 100
}

func productFromModel(row sqlc.Product) domain.Product {
	return domain.Product{
		ID:          row.ID,
		Name:        row.Name,
		Description: row.Description,
		Barcode:     row.Barcode,
		Price:       row.Price,
		Cost:        row.Cost,
		Margin:      numericToFloat(row.Margin),
		Type:        row.Type,
		CreatedAt:   row.CreatedAt,
		UpdatedAt:   row.UpdatedAt,
	}
}

func imageFromModel(row sqlc.ProductImage) domain.ProductImage {
	return domain.ProductImage{
		ID:           row.ID,
		ProductID:    row.ProductID,
		URL:          "/downloads/" + strings.TrimPrefix(filepath.ToSlash(row.FilePath), "/"),
		OriginalName: row.OriginalName,
		MimeType:     row.MimeType,
		SizeBytes:    row.SizeBytes,
		SortOrder:    row.SortOrder,
		CreatedAt:    row.CreatedAt,
		UpdatedAt:    row.UpdatedAt,
	}
}

func removeFiles(paths []string) {
	for _, path := range paths {
		if path != "" {
			_ = os.Remove(path)
		}
	}
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

func validationField(field, message string) *apperr.Error {
	return apperr.Validation("Datos inválidos.", []apperr.FieldError{{Field: field, Message: message}})
}
