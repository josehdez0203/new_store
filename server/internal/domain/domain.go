// Package domain contiene los tipos de negocio compartidos por los servicios
// y la capa HTTP, independientes de sqlc y de Gin.
package domain

import (
	"time"

	"github.com/google/uuid"
)

// User es un usuario del sistema con sus roles y permisos efectivos.
type User struct {
	ID          uuid.UUID
	Email       string
	FullName    string
	IsActive    bool
	Roles       []string
	Permissions []string
	LastLoginAt *time.Time
	CreatedAt   time.Time
	UpdatedAt   time.Time
}

// HasRole indica si el usuario tiene el rol solicitado.
func (u User) HasRole(name string) bool {
	for _, role := range u.Roles {
		if role == name {
			return true
		}
	}
	return false
}

// Role es un rol con sus contadores y, opcionalmente, sus permisos.
type Role struct {
	ID              uuid.UUID
	Name            string
	Description     *string
	IsSystem        bool
	UserCount       int64
	PermissionCount int64
	Permissions     []Permission
	CreatedAt       time.Time
	UpdatedAt       time.Time
}

// Permission es un permiso atómico del catálogo RBAC.
type Permission struct {
	ID          uuid.UUID
	Name        string
	Description *string
	Module      string
	RoleCount   int64
	CreatedAt   time.Time
	UpdatedAt   time.Time
}

// ProductImage es una fotografía del catálogo.
type ProductImage struct {
	ID           uuid.UUID
	ProductID    uuid.UUID
	URL          string
	OriginalName *string
	MimeType     string
	SizeBytes    int64
	SortOrder    int32
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

// Customer es un cliente del negocio.
type Customer struct {
	ID         uuid.UUID
	Name       string
	Address    *string
	City       *string
	PostalCode *string
	Phone      *string
	Email      *string
	Status     string
	CreatedAt  time.Time
	UpdatedAt  time.Time
}

// CreditSettings es la configuración de financiamiento de la empresa.
type CreditSettings struct {
	DownPaymentOptions  []float64
	CreditMonths        []int32
	MonthlyInterestRate float64
	UpdatedAt           time.Time
}

// SaleItem es una partida de la venta.
type SaleItem struct {
	ID          uuid.UUID
	ProductID   uuid.UUID
	ProductName string
	Quantity    int32
	UnitPrice   float64
	Subtotal    float64
}

// SalePayment es un pago del plan (anticipo, mensualidad o contado).
type SalePayment struct {
	ID                uuid.UUID
	InstallmentNumber int32
	Kind              string
	DueDate           time.Time
	Amount            float64
}

// Sale es una venta o cotización con su detalle y plan de pagos.
type Sale struct {
	ID                  uuid.UUID
	SaleNumber          string
	ClientID            uuid.UUID
	ClientName          string
	ClientPhone         *string
	ClientEmail         *string
	SellerID            uuid.UUID
	SellerName          string
	SaleDate            time.Time
	Status              string
	PaymentType         string
	DownPaymentPercent  float64
	DownPayment         float64
	FinancedAmount      float64
	MonthlyInterestRate float64
	Months              int32
	TotalInterest       float64
	Total               float64
	Items               []SaleItem
	Payments            []SalePayment
	CreatedAt           time.Time
	UpdatedAt           time.Time
}

// Product es un producto o servicio del catálogo.
type Product struct {
	ID          uuid.UUID
	Name        string
	Description *string
	Barcode     *string
	Price       float64
	Cost        float64
	Margin      float64
	Type        string
	Images      []ProductImage
	CreatedAt   time.Time
	UpdatedAt   time.Time
}

// Session representa una sesión activa (refresh token) sin exponer su hash.
type Session struct {
	ID         uuid.UUID
	UserAgent  *string
	IPAddress  *string
	ExpiresAt  time.Time
	RevokedAt  *time.Time
	LastUsedAt time.Time
	CreatedAt  time.Time
}

// AuthContext es el contexto resuelto en cada petición autenticada.
type AuthContext struct {
	User             User
	SessionID        uuid.UUID
	SessionExpiresAt time.Time
}

// HasPermission indica si el contexto tiene el permiso solicitado.
// El permiso comodín "*" concede acceso total.
func (a AuthContext) HasPermission(name string) bool {
	for _, permission := range a.User.Permissions {
		if permission == name || permission == "*" {
			return true
		}
	}
	return false
}

// Tokens es el par de tokens emitido por el servicio de autenticación.
type Tokens struct {
	AccessToken      string
	RefreshToken     string
	AccessExpiresAt  time.Time
	RefreshExpiresAt time.Time
}

// DashboardStats agrupa las métricas principales del panel.
type DashboardStats struct {
	UsersTotal       int64
	UsersActive      int64
	RolesTotal       int64
	PermissionsTotal int64
	ActiveSessions   int64
	UsersByRole      []RoleCount
}

// RoleCount es la cantidad de usuarios asignados a un rol.
type RoleCount struct {
	Role  string
	Total int64
}
