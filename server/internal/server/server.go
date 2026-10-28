// Package server expone el API REST con Gin.
package server

import (
	"context"
	"log/slog"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/jhc/credit-store/server/internal/auth"
	"github.com/jhc/credit-store/server/internal/config"
	"github.com/jhc/credit-store/server/internal/customers"
	"github.com/jhc/credit-store/server/internal/dashboard"
	"github.com/jhc/credit-store/server/internal/products"
	"github.com/jhc/credit-store/server/internal/rbac"
	"github.com/jhc/credit-store/server/internal/sales"
	"github.com/jhc/credit-store/server/internal/users"
)

// Services agrupa los servicios de negocio usados por los handlers.
type Services struct {
	Auth      *auth.Service
	Users     *users.Service
	RBAC      *rbac.Service
	Dashboard *dashboard.Service
	Products  *products.Service
	Customers *customers.Service
	Sales     *sales.Service
}

// API contiene las dependencias compartidas por los handlers.
type API struct {
	cfg      *config.Config
	log      *slog.Logger
	db       *pgxpool.Pool
	services Services
}

// NewRouter construye el router con todas las rutas y middleware.
func NewRouter(cfg *config.Config, log *slog.Logger, db *pgxpool.Pool, services Services) *gin.Engine {
	if cfg.IsProduction() {
		gin.SetMode(gin.ReleaseMode)
	} else {
		gin.SetMode(gin.DebugMode)
	}

	api := &API{cfg: cfg, log: log, db: db, services: services}

	router := gin.New()
	router.HandleMethodNotAllowed = true
	router.MaxMultipartMemory = 64 << 20
	_ = router.SetTrustedProxies(nil)

	router.Use(requestIDMiddleware())
	router.Use(requestLogger())
	router.Use(api.recoveryMiddleware())
	router.Use(securityHeadersMiddleware())
	router.Use(corsMiddleware(cfg))

	router.GET("/health", api.health)
	router.GET("/ready", api.ready)
	router.Static("/downloads", cfg.DownloadsDir)

	v1 := router.Group("/api/v1")

	// Públicas
	v1.POST("/auth/login", api.login)
	v1.POST("/auth/refresh", api.refresh)

	// Autenticadas
	authed := v1.Group("")
	authed.Use(api.authMiddleware())
	{
		authed.GET("/auth/me", api.me)
		authed.PATCH("/auth/me", api.updateMe)
		authed.POST("/auth/logout", api.logout)
		authed.POST("/auth/logout-all", api.logoutAll)
		authed.POST("/auth/change-password", api.changePassword)
		authed.GET("/auth/sessions", api.listSessions)
		authed.DELETE("/auth/sessions/:id", api.revokeSession)

		authed.GET("/dashboard/stats", api.requirePermission("dashboard.read"), api.dashboardStats)

		userRoutes := authed.Group("/users")
		{
			userRoutes.GET("", api.requirePermission("users.read"), api.listUsers)
			userRoutes.POST("", api.requirePermission("users.create"), api.createUser)
			userRoutes.GET("/:id", api.requirePermission("users.read"), api.getUser)
			userRoutes.PATCH("/:id", api.requirePermission("users.update"), api.updateUser)
			userRoutes.DELETE("/:id", api.requirePermission("users.delete"), api.deleteUser)
			userRoutes.PUT("/:id/roles", api.requirePermission("users.assign_roles"), api.setUserRoles)
			userRoutes.POST("/:id/reset-password", api.requirePermission("users.update"), api.resetUserPassword)
		}

		roleRoutes := authed.Group("/roles")
		{
			roleRoutes.GET("", api.requirePermission("roles.read"), api.listRoles)
			roleRoutes.POST("", api.requirePermission("roles.create"), api.createRole)
			roleRoutes.GET("/:id", api.requirePermission("roles.read"), api.getRole)
			roleRoutes.PUT("/:id", api.requirePermission("roles.update"), api.updateRole)
			roleRoutes.DELETE("/:id", api.requirePermission("roles.delete"), api.deleteRole)
			roleRoutes.PUT("/:id/permissions", api.requirePermission("roles.update"), api.setRolePermissions)
		}

		permissionRoutes := authed.Group("/permissions")
		{
			permissionRoutes.GET("", api.requirePermission("permissions.read"), api.listPermissions)
			permissionRoutes.POST("", api.requirePermission("permissions.create"), api.createPermission)
			permissionRoutes.GET("/:id", api.requirePermission("permissions.read"), api.getPermission)
			permissionRoutes.PUT("/:id", api.requirePermission("permissions.update"), api.updatePermission)
			permissionRoutes.DELETE("/:id", api.requirePermission("permissions.delete"), api.deletePermission)
		}

		saleRoutes := authed.Group("/sales")
		{
			saleRoutes.GET("", api.requirePermission("sales.read"), api.listSales)
			saleRoutes.POST("", api.requirePermission("sales.create"), api.createSale)
			saleRoutes.GET("/:id", api.requirePermission("sales.read"), api.getSale)
			saleRoutes.PUT("/:id", api.requirePermission("sales.update"), api.updateSale)
			saleRoutes.PATCH("/:id/status", api.requirePermission("sales.update"), api.updateSaleStatus)
			saleRoutes.POST("/:id/cancel", api.requirePermission("sales.cancel"), api.cancelSale)
		}

		creditSettingsRoutes := authed.Group("/credit-settings")
		{
			creditSettingsRoutes.GET("", api.requirePermission("sales.read"), api.getCreditSettings)
			creditSettingsRoutes.PUT("", api.requirePermission("credit_settings.update"), api.updateCreditSettings)
		}

		customerRoutes := authed.Group("/customers")
		{
			customerRoutes.GET("", api.requirePermission("customers.read"), api.listCustomers)
			customerRoutes.POST("", api.requirePermission("customers.create"), api.createCustomer)
			customerRoutes.GET("/:id", api.requirePermission("customers.read"), api.getCustomer)
			customerRoutes.PUT("/:id", api.requirePermission("customers.update"), api.updateCustomer)
			customerRoutes.DELETE("/:id", api.requirePermission("customers.delete"), api.deleteCustomer)
		}

		productRoutes := authed.Group("/products")
		{
			productRoutes.GET("", api.requirePermission("products.read"), api.listProducts)
			productRoutes.POST("", api.requirePermission("products.create"), api.createProduct)
			productRoutes.GET("/:id", api.requirePermission("products.read"), api.getProduct)
			productRoutes.PUT("/:id", api.requirePermission("products.update"), api.updateProduct)
			productRoutes.DELETE("/:id", api.requirePermission("products.delete"), api.deleteProduct)

			productRoutes.GET("/:id/images", api.requirePermission("products.read"), api.listProductImages)
			productRoutes.POST("/:id/images", api.requirePermission("products.manage_images"), api.addProductImages)
			productRoutes.PUT("/:id/images/:image_id", api.requirePermission("products.manage_images"), api.replaceProductImage)
			productRoutes.DELETE("/:id/images/:image_id", api.requirePermission("products.manage_images"), api.deleteProductImage)
		}
	}

	router.NoRoute(func(c *gin.Context) {
		api.fail(c, notFoundRoute())
	})
	router.NoMethod(func(c *gin.Context) {
		api.fail(c, methodNotAllowed())
	})

	return router
}

func (a *API) health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":  "ok",
		"service": "credit-store-api",
		"time":    time.Now().UTC(),
	})
}

func (a *API) ready(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
	defer cancel()

	if err := a.db.Ping(ctx); err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "unavailable",
			"error":  "database",
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"status": "ready",
	})
}
