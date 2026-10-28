package server

import (
	"time"

	"github.com/google/uuid"

	"github.com/jhc/credit-store/server/internal/auth"
	"github.com/jhc/credit-store/server/internal/domain"
)

type userResponse struct {
	ID          string     `json:"id"`
	Email       string     `json:"email"`
	FullName    string     `json:"full_name"`
	IsActive    bool       `json:"is_active"`
	Roles       []string   `json:"roles"`
	Permissions []string   `json:"permissions,omitempty"`
	LastLoginAt *time.Time `json:"last_login_at"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

type permissionResponse struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	Description *string   `json:"description"`
	Module      string    `json:"module"`
	RoleCount   int64     `json:"role_count"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

type roleResponse struct {
	ID              string               `json:"id"`
	Name            string               `json:"name"`
	Description     *string              `json:"description"`
	IsSystem        bool                 `json:"is_system"`
	UserCount       int64                `json:"user_count"`
	PermissionCount int64                `json:"permission_count"`
	Permissions     []permissionResponse `json:"permissions,omitempty"`
	CreatedAt       time.Time            `json:"created_at"`
	UpdatedAt       time.Time            `json:"updated_at"`
}

type sessionResponse struct {
	ID         string     `json:"id"`
	UserAgent  *string    `json:"user_agent"`
	IPAddress  *string    `json:"ip_address"`
	ExpiresAt  time.Time  `json:"expires_at"`
	RevokedAt  *time.Time `json:"revoked_at"`
	LastUsedAt time.Time  `json:"last_used_at"`
	CreatedAt  time.Time  `json:"created_at"`
	Current    bool       `json:"current"`
}

type authResponse struct {
	AccessToken      string       `json:"access_token"`
	RefreshToken     string       `json:"refresh_token"`
	TokenType        string       `json:"token_type"`
	ExpiresIn        int64        `json:"expires_in"`
	RefreshExpiresIn int64        `json:"refresh_expires_in"`
	User             userResponse `json:"user"`
}

type creditSettingsResponse struct {
	DownPaymentOptions  []float64 `json:"down_payment_options"`
	CreditMonths        []int32   `json:"credit_months"`
	MonthlyInterestRate float64   `json:"monthly_interest_rate"`
	UpdatedAt           time.Time `json:"updated_at"`
}

type saleItemResponse struct {
	ID          string  `json:"id"`
	ProductID   string  `json:"product_id"`
	ProductName string  `json:"product_name"`
	Quantity    int32   `json:"quantity"`
	UnitPrice   float64 `json:"unit_price"`
	Subtotal    float64 `json:"subtotal"`
}

type salePaymentResponse struct {
	ID                string  `json:"id"`
	InstallmentNumber int32   `json:"installment_number"`
	Kind              string  `json:"kind"`
	DueDate           string  `json:"due_date"`
	Amount            float64 `json:"amount"`
}

type saleResponse struct {
	ID                  string                `json:"id"`
	SaleNumber          string                `json:"sale_number"`
	ClientID            string                `json:"client_id"`
	ClientName          string                `json:"client_name"`
	ClientPhone         *string               `json:"client_phone"`
	ClientEmail         *string               `json:"client_email"`
	SellerID            string                `json:"seller_id"`
	SellerName          string                `json:"seller_name"`
	SaleDate            string                `json:"sale_date"`
	Status              string                `json:"status"`
	PaymentType         string                `json:"payment_type"`
	DownPaymentPercent  float64               `json:"down_payment_percent"`
	DownPayment         float64               `json:"down_payment"`
	FinancedAmount      float64               `json:"financed_amount"`
	MonthlyInterestRate float64               `json:"monthly_interest_rate"`
	Months              int32                 `json:"months"`
	TotalInterest       float64               `json:"total_interest"`
	Total               float64               `json:"total"`
	Items               []saleItemResponse    `json:"items"`
	Payments            []salePaymentResponse `json:"payments"`
	CreatedAt           time.Time             `json:"created_at"`
	UpdatedAt           time.Time             `json:"updated_at"`
}

type customerResponse struct {
	ID         string    `json:"id"`
	Name       string    `json:"name"`
	Address    *string   `json:"address"`
	City       *string   `json:"city"`
	PostalCode *string   `json:"postal_code"`
	Phone      *string   `json:"phone"`
	Email      *string   `json:"email"`
	Status     string    `json:"status"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

type productImageResponse struct {
	ID           string    `json:"id"`
	URL          string    `json:"url"`
	OriginalName *string   `json:"original_name"`
	MimeType     string    `json:"mime_type"`
	SizeBytes    int64     `json:"size_bytes"`
	SortOrder    int32     `json:"sort_order"`
	CreatedAt    time.Time `json:"created_at"`
}

type productResponse struct {
	ID          string                 `json:"id"`
	Name        string                 `json:"name"`
	Description *string                `json:"description"`
	Barcode     *string                `json:"barcode"`
	Price       float64                `json:"price"`
	Cost        float64                `json:"cost"`
	Margin      *float64               `json:"margin,omitempty"`
	Type        string                 `json:"type"`
	Images      []productImageResponse `json:"images"`
	ImagesCount int                    `json:"images_count"`
	CreatedAt   time.Time              `json:"created_at"`
	UpdatedAt   time.Time              `json:"updated_at"`
}

type roleCountResponse struct {
	Role  string `json:"role"`
	Total int64  `json:"total"`
}

type dashboardStatsResponse struct {
	UsersTotal       int64               `json:"users_total"`
	UsersActive      int64               `json:"users_active"`
	RolesTotal       int64               `json:"roles_total"`
	PermissionsTotal int64               `json:"permissions_total"`
	ActiveSessions   int64               `json:"active_sessions"`
	UsersByRole      []roleCountResponse `json:"users_by_role"`
}

func userToResponse(user domain.User) userResponse {
	roles := user.Roles
	if roles == nil {
		roles = []string{}
	}
	permissions := user.Permissions
	if len(permissions) == 0 {
		permissions = nil
	}
	return userResponse{
		ID:          user.ID.String(),
		Email:       user.Email,
		FullName:    user.FullName,
		IsActive:    user.IsActive,
		Roles:       roles,
		Permissions: permissions,
		LastLoginAt: user.LastLoginAt,
		CreatedAt:   user.CreatedAt,
		UpdatedAt:   user.UpdatedAt,
	}
}

func usersToResponse(users []domain.User) []userResponse {
	result := make([]userResponse, 0, len(users))
	for _, user := range users {
		result = append(result, userToResponse(user))
	}
	return result
}

func permissionToResponse(permission domain.Permission) permissionResponse {
	return permissionResponse{
		ID:          permission.ID.String(),
		Name:        permission.Name,
		Description: permission.Description,
		Module:      permission.Module,
		RoleCount:   permission.RoleCount,
		CreatedAt:   permission.CreatedAt,
		UpdatedAt:   permission.UpdatedAt,
	}
}

func permissionsToResponse(permissions []domain.Permission) []permissionResponse {
	result := make([]permissionResponse, 0, len(permissions))
	for _, permission := range permissions {
		result = append(result, permissionToResponse(permission))
	}
	return result
}

func roleToResponse(role domain.Role) roleResponse {
	var permissions []permissionResponse
	if role.Permissions != nil {
		permissions = permissionsToResponse(role.Permissions)
	}
	return roleResponse{
		ID:              role.ID.String(),
		Name:            role.Name,
		Description:     role.Description,
		IsSystem:        role.IsSystem,
		UserCount:       role.UserCount,
		PermissionCount: role.PermissionCount,
		Permissions:     permissions,
		CreatedAt:       role.CreatedAt,
		UpdatedAt:       role.UpdatedAt,
	}
}

func rolesToResponse(roles []domain.Role) []roleResponse {
	result := make([]roleResponse, 0, len(roles))
	for _, role := range roles {
		result = append(result, roleToResponse(role))
	}
	return result
}

func creditSettingsToResponse(settings domain.CreditSettings) creditSettingsResponse {
	return creditSettingsResponse{
		DownPaymentOptions:  settings.DownPaymentOptions,
		CreditMonths:        settings.CreditMonths,
		MonthlyInterestRate: settings.MonthlyInterestRate,
		UpdatedAt:           settings.UpdatedAt,
	}
}

func saleToResponse(sale domain.Sale) saleResponse {
	items := make([]saleItemResponse, 0, len(sale.Items))
	for _, item := range sale.Items {
		items = append(items, saleItemResponse{
			ID:          item.ID.String(),
			ProductID:   item.ProductID.String(),
			ProductName: item.ProductName,
			Quantity:    item.Quantity,
			UnitPrice:   item.UnitPrice,
			Subtotal:    item.Subtotal,
		})
	}
	payments := make([]salePaymentResponse, 0, len(sale.Payments))
	for _, payment := range sale.Payments {
		payments = append(payments, salePaymentResponse{
			ID:                payment.ID.String(),
			InstallmentNumber: payment.InstallmentNumber,
			Kind:              payment.Kind,
			DueDate:           payment.DueDate.Format("2006-01-02"),
			Amount:            payment.Amount,
		})
	}
	return saleResponse{
		ID:                  sale.ID.String(),
		SaleNumber:          sale.SaleNumber,
		ClientID:            sale.ClientID.String(),
		ClientName:          sale.ClientName,
		ClientPhone:         sale.ClientPhone,
		ClientEmail:         sale.ClientEmail,
		SellerID:            sale.SellerID.String(),
		SellerName:          sale.SellerName,
		SaleDate:            sale.SaleDate.Format("2006-01-02"),
		Status:              sale.Status,
		PaymentType:         sale.PaymentType,
		DownPaymentPercent:  sale.DownPaymentPercent,
		DownPayment:         sale.DownPayment,
		FinancedAmount:      sale.FinancedAmount,
		MonthlyInterestRate: sale.MonthlyInterestRate,
		Months:              sale.Months,
		TotalInterest:       sale.TotalInterest,
		Total:               sale.Total,
		Items:               items,
		Payments:            payments,
		CreatedAt:           sale.CreatedAt,
		UpdatedAt:           sale.UpdatedAt,
	}
}

func salesToResponse(sales []domain.Sale) []saleResponse {
	result := make([]saleResponse, 0, len(sales))
	for _, sale := range sales {
		result = append(result, saleToResponse(sale))
	}
	return result
}

func customerToResponse(customer domain.Customer) customerResponse {
	return customerResponse{
		ID:         customer.ID.String(),
		Name:       customer.Name,
		Address:    customer.Address,
		City:       customer.City,
		PostalCode: customer.PostalCode,
		Phone:      customer.Phone,
		Email:      customer.Email,
		Status:     customer.Status,
		CreatedAt:  customer.CreatedAt,
		UpdatedAt:  customer.UpdatedAt,
	}
}

func customersToResponse(customers []domain.Customer) []customerResponse {
	result := make([]customerResponse, 0, len(customers))
	for _, customer := range customers {
		result = append(result, customerToResponse(customer))
	}
	return result
}

func productToResponse(product domain.Product, showMargin bool) productResponse {
	images := productImagesToResponse(product.Images)
	var margin *float64
	if showMargin {
		value := product.Margin
		margin = &value
	}
	return productResponse{
		ID:          product.ID.String(),
		Name:        product.Name,
		Description: product.Description,
		Barcode:     product.Barcode,
		Price:       product.Price,
		Cost:        product.Cost,
		Margin:      margin,
		Type:        product.Type,
		Images:      images,
		ImagesCount: len(images),
		CreatedAt:   product.CreatedAt,
		UpdatedAt:   product.UpdatedAt,
	}
}

func productImagesToResponse(images []domain.ProductImage) []productImageResponse {
	result := make([]productImageResponse, 0, len(images))
	for _, image := range images {
		result = append(result, productImageResponse{
			ID:           image.ID.String(),
			URL:          image.URL,
			OriginalName: image.OriginalName,
			MimeType:     image.MimeType,
			SizeBytes:    image.SizeBytes,
			SortOrder:    image.SortOrder,
			CreatedAt:    image.CreatedAt,
		})
	}
	return result
}

func productsToResponse(products []domain.Product, showMargin bool) []productResponse {
	result := make([]productResponse, 0, len(products))
	for _, product := range products {
		result = append(result, productToResponse(product, showMargin))
	}
	return result
}

func sessionsToResponse(sessions []domain.Session, currentSessionID uuid.UUID) []sessionResponse {
	result := make([]sessionResponse, 0, len(sessions))
	for _, session := range sessions {
		result = append(result, sessionResponse{
			ID:         session.ID.String(),
			UserAgent:  session.UserAgent,
			IPAddress:  session.IPAddress,
			ExpiresAt:  session.ExpiresAt,
			RevokedAt:  session.RevokedAt,
			LastUsedAt: session.LastUsedAt,
			CreatedAt:  session.CreatedAt,
			Current:    session.ID == currentSessionID,
		})
	}
	return result
}

func authToResponse(result *auth.LoginResult) authResponse {
	now := time.Now().UTC()
	expiresIn := int64(result.Tokens.AccessExpiresAt.Sub(now).Seconds())
	if expiresIn < 0 {
		expiresIn = 0
	}
	refreshExpiresIn := int64(result.Tokens.RefreshExpiresAt.Sub(now).Seconds())
	if refreshExpiresIn < 0 {
		refreshExpiresIn = 0
	}

	return authResponse{
		AccessToken:      result.Tokens.AccessToken,
		RefreshToken:     result.Tokens.RefreshToken,
		TokenType:        "Bearer",
		ExpiresIn:        expiresIn,
		RefreshExpiresIn: refreshExpiresIn,
		User:             userToResponse(result.User),
	}
}

func dashboardToResponse(stats domain.DashboardStats) dashboardStatsResponse {
	byRole := make([]roleCountResponse, 0, len(stats.UsersByRole))
	for _, item := range stats.UsersByRole {
		byRole = append(byRole, roleCountResponse{Role: item.Role, Total: item.Total})
	}
	return dashboardStatsResponse{
		UsersTotal:       stats.UsersTotal,
		UsersActive:      stats.UsersActive,
		RolesTotal:       stats.RolesTotal,
		PermissionsTotal: stats.PermissionsTotal,
		ActiveSessions:   stats.ActiveSessions,
		UsersByRole:      byRole,
	}
}
