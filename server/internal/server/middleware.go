package server

import (
	"fmt"
	"net"
	"net/http"
	"net/url"
	"os"
	"runtime/debug"
	"strings"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/jhc/credit-store/server/internal/apperr"
	"github.com/jhc/credit-store/server/internal/config"
	"github.com/jhc/credit-store/server/internal/domain"
)

const (
	requestIDKey     = "request_id"
	authContextKey   = "auth_context"
	maxRequestIDSize = 128
)

func requestIDMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		requestID := strings.TrimSpace(c.GetHeader("X-Request-ID"))
		if requestID == "" || len(requestID) > maxRequestIDSize || strings.ContainsAny(requestID, "\r\n\t ") {
			requestID = uuid.NewString()
		}
		c.Set(requestIDKey, requestID)
		c.Header("X-Request-ID", requestID)
		c.Next()
	}
}

const (
	ansiReset   = "\033[0m"
	ansiRed     = "\033[31m"
	ansiGreen   = "\033[32m"
	ansiYellow  = "\033[33m"
	ansiBlue    = "\033[34m"
	ansiMagenta = "\033[35m"
	ansiCyan    = "\033[36m"
	ansiGray    = "\033[90m"
)

// requestLogger imprime una línea compacta por petición:
//
//	[2026/10/28-13:52:28] GET     auth/login                  200 192.168.1.20
//
// El timestamp, el método y el status llevan color ANSI. La ruta se muestra
// sin el prefijo /api/v1 y la IP es la del cliente que vio Nginx.
func requestLogger() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Next()

		method := c.Request.Method
		status := c.Writer.Status()
		path := requestLogPath(c.Request.URL.Path)
		timestamp := time.Now().Format("2006/01/02-15:04:05")

		fmt.Fprintf(os.Stdout, "%s %s %-42s %s %s\n",
			colorize("["+timestamp+"]", ansiGray),
			colorize(fmt.Sprintf("%-7s", method), methodColor(method)),
			path,
			colorize(fmt.Sprintf("%3d", status), statusColor(status)),
			clientIP(c),
		)
	}
}

func requestLogPath(path string) string {
	if path == "" || path == "/" {
		return "/"
	}
	switch {
	case path == "/api/v1":
		return "/"
	case strings.HasPrefix(path, "/api/v1/"):
		path = strings.TrimPrefix(path, "/api/v1/")
	}
	path = strings.TrimPrefix(path, "/")
	if path == "" {
		return "/"
	}
	return path
}

func methodColor(method string) string {
	switch strings.ToUpper(method) {
	case http.MethodGet:
		return ansiCyan
	case http.MethodPost:
		return ansiGreen
	case http.MethodPut:
		return ansiYellow
	case http.MethodPatch:
		return ansiMagenta
	case http.MethodDelete:
		return ansiRed
	case http.MethodHead:
		return ansiBlue
	default:
		return ansiGray
	}
}

func statusColor(status int) string {
	switch {
	case status >= 500:
		return ansiRed
	case status >= 400:
		return ansiYellow
	case status >= 300:
		return ansiCyan
	case status >= 200:
		return ansiGreen
	default:
		return ansiGray
	}
}

func colorize(value, color string) string {
	return color + value + ansiReset
}

// clientIP prioriza X-Real-IP/X-Forwarded-For puestos por Nginx y siempre
// devuelve una representación IPv4. La API solo escucha en loopback en
// producción, así que estas cabeceras son confiables.
func clientIP(c *gin.Context) string {
	if ip := validIPv4(c.GetHeader("X-Real-IP")); ip != "" {
		return ip
	}
	if forwarded := c.GetHeader("X-Forwarded-For"); forwarded != "" {
		for _, part := range strings.Split(forwarded, ",") {
			if ip := validIPv4(part); ip != "" {
				return ip
			}
		}
	}
	if ip := validIPv4(c.ClientIP()); ip != "" {
		return ip
	}
	if host, _, err := net.SplitHostPort(c.Request.RemoteAddr); err == nil {
		if ip := validIPv4(host); ip != "" {
			return ip
		}
	}
	// Un cliente exclusivamente IPv6 no tiene representación IPv4.
	return "0.0.0.0"
}

func validIPv4(value string) string {
	value = strings.TrimSpace(value)
	ip := net.ParseIP(value)
	if ip == nil {
		return ""
	}
	if ip.Equal(net.IPv6loopback) {
		return "127.0.0.1"
	}
	if v4 := ip.To4(); v4 != nil {
		return v4.String()
	}
	return ""
}

func (a *API) recoveryMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		defer func() {
			if recovered := recover(); recovered != nil {
				a.log.Error("panic recuperado",
					"panic", recovered,
					"path", c.Request.URL.Path,
					"request_id", requestIDFrom(c),
					"stack", string(debug.Stack()),
				)
				a.fail(c, apperr.Internal(nil))
			}
		}()
		c.Next()
	}
}

func securityHeadersMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("X-Content-Type-Options", "nosniff")
		c.Header("X-Frame-Options", "DENY")
		c.Header("Referrer-Policy", "no-referrer")
		c.Header("Cache-Control", "no-store")
		c.Next()
	}
}

func corsMiddleware(cfg *config.Config) gin.HandlerFunc {
	corsConfig := cors.Config{
		AllowMethods: []string{
			http.MethodGet,
			http.MethodPost,
			http.MethodPut,
			http.MethodPatch,
			http.MethodDelete,
			http.MethodOptions,
		},
		AllowHeaders:     []string{"Origin", "Content-Type", "Accept", "Authorization", "X-Request-ID"},
		ExposeHeaders:    []string{"X-Request-ID"},
		AllowCredentials: false,
		MaxAge:           12 * time.Hour,
		AllowOriginFunc: func(origin string) bool {
			if origin == "" {
				return false
			}
			if cfg.IsDevelopment() {
				parsed, err := url.Parse(origin)
				if err != nil {
					return false
				}
				switch parsed.Hostname() {
				case "localhost", "127.0.0.1", "::1":
					return true
				}
			}
			for _, allowed := range cfg.CORSOrigins {
				if strings.EqualFold(strings.TrimSuffix(allowed, "/"), strings.TrimSuffix(origin, "/")) {
					return true
				}
			}
			return false
		},
	}
	return cors.New(corsConfig)
}

func (a *API) authMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		token, ok := bearerToken(c.GetHeader("Authorization"))
		if !ok {
			c.Header("WWW-Authenticate", "Bearer")
			a.fail(c, apperr.New(http.StatusUnauthorized, "unauthorized",
				"Se requiere un access token Bearer para acceder a este recurso."))
			return
		}

		claims, err := a.services.Auth.ParseAccessToken(token)
		if err != nil {
			c.Header("WWW-Authenticate", "Bearer")
			a.fail(c, apperr.New(http.StatusUnauthorized, "invalid_token",
				"El access token es inválido o ha expirado."))
			return
		}

		sessionID, err := uuid.Parse(claims.SessionID)
		if err != nil {
			a.fail(c, apperr.New(http.StatusUnauthorized, "invalid_token", "La sesión del token es inválida."))
			return
		}

		authCtx, err := a.services.Auth.GetAuthContext(c.Request.Context(), sessionID)
		if err != nil {
			a.fail(c, err)
			return
		}
		if authCtx.User.ID.String() != claims.Subject {
			a.fail(c, apperr.New(http.StatusUnauthorized, "invalid_token",
				"El token no corresponde al usuario de la sesión."))
			return
		}

		c.Set(authContextKey, authCtx)
		c.Next()
	}
}

func (a *API) requirePermission(permission string) gin.HandlerFunc {
	return func(c *gin.Context) {
		authCtx := authContextFrom(c)
		if authCtx == nil {
			a.fail(c, apperr.Unauthorized("Se requiere autenticación."))
			return
		}
		if !authCtx.HasPermission(permission) {
			a.log.Warn("permiso denegado",
				"user_id", authCtx.User.ID,
				"email", authCtx.User.Email,
				"permission", permission,
				"path", c.Request.URL.Path,
			)
			a.fail(c, apperr.Forbidden("No tienes permisos para realizar esta acción."))
			return
		}
		c.Next()
	}
}

func bearerToken(header string) (string, bool) {
	parts := strings.SplitN(strings.TrimSpace(header), " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
		return "", false
	}
	token := strings.TrimSpace(parts[1])
	if token == "" {
		return "", false
	}
	return token, true
}

func authContextFrom(c *gin.Context) *domain.AuthContext {
	value, ok := c.Get(authContextKey)
	if !ok {
		return nil
	}
	authCtx, ok := value.(*domain.AuthContext)
	if !ok {
		return nil
	}
	return authCtx
}

func requestIDFrom(c *gin.Context) string {
	value, ok := c.Get(requestIDKey)
	if !ok {
		return ""
	}
	requestID, _ := value.(string)
	return requestID
}

func notFoundRoute() error {
	return apperr.NotFound("La ruta solicitada no existe.")
}

func methodNotAllowed() error {
	return apperr.New(http.StatusMethodNotAllowed, "method_not_allowed", "El método HTTP no está permitido para esta ruta.")
}
