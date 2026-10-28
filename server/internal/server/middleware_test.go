package server

import (
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestRequestLogPath(t *testing.T) {
	cases := map[string]string{
		"/api/v1/auth/login":        "auth/login",
		"/api/v1/sales":             "sales",
		"/api/v1/":                  "/",
		"/api/v1":                   "/",
		"/health":                   "health",
		"/downloads/products/a.png": "downloads/products/a.png",
		"/":                         "/",
	}
	for input, expected := range cases {
		if got := requestLogPath(input); got != expected {
			t.Errorf("requestLogPath(%q) = %q; want %q", input, got, expected)
		}
	}
}

func TestClientIP(t *testing.T) {
	gin.SetMode(gin.TestMode)

	contextWith := func(headers map[string]string, remote string) *gin.Context {
		c, _ := gin.CreateTestContext(httptest.NewRecorder())
		c.Request = httptest.NewRequest(http.MethodGet, "/api/v1/auth/login", nil)
		c.Request.RemoteAddr = remote
		for key, value := range headers {
			c.Request.Header.Set(key, value)
		}
		return c
	}

	if got := clientIP(contextWith(map[string]string{"X-Real-IP": "203.0.113.10"}, "172.20.0.1:1234")); got != "203.0.113.10" {
		t.Fatalf("X-Real-IP = %q", got)
	}
	if got := clientIP(contextWith(map[string]string{"X-Forwarded-For": "198.51.100.7, 203.0.113.10"}, "172.20.0.1:1234")); got != "198.51.100.7" {
		t.Fatalf("X-Forwarded-For = %q", got)
	}
	if got := clientIP(contextWith(map[string]string{"X-Real-IP": "::1"}, "192.0.2.55:4321")); got != "127.0.0.1" {
		t.Fatalf("IPv6 loopback = %q", got)
	}
	if got := clientIP(contextWith(map[string]string{"X-Real-IP": "::ffff:203.0.113.10"}, "172.20.0.1:1234")); got != "203.0.113.10" {
		t.Fatalf("IPv4-mapped = %q", got)
	}
	if got := clientIP(contextWith(map[string]string{"X-Forwarded-For": "2001:db8::1, 198.51.100.7"}, "172.20.0.1:1234")); got != "198.51.100.7" {
		t.Fatalf("X-Forwarded-For IPv6/IPv4 = %q", got)
	}
	if got := clientIP(contextWith(nil, "192.0.2.55:4321")); got != "192.0.2.55" {
		t.Fatalf("remote addr = %q", got)
	}
	if got := clientIP(contextWith(nil, "[::1]:4321")); got != "127.0.0.1" {
		t.Fatalf("IPv6 remote loopback = %q", got)
	}
}

func TestRequestLoggerFormat(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(requestLogger())
	router.GET("/api/v1/auth/login", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})

	oldStdout := os.Stdout
	read, write, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	os.Stdout = write
	defer func() { os.Stdout = oldStdout }()

	request := httptest.NewRequest(http.MethodGet, "/api/v1/auth/login", nil)
	request.Header.Set("X-Real-IP", "203.0.113.10")
	router.ServeHTTP(httptest.NewRecorder(), request)
	_ = write.Close()
	os.Stdout = oldStdout

	output, err := io.ReadAll(read)
	if err != nil {
		t.Fatal(err)
	}
	line := string(output)
	if !strings.Contains(line, "auth/login") {
		t.Fatalf("log no contiene la ruta simplificada: %q", line)
	}
	if strings.Contains(line, "/api/v1") {
		t.Fatalf("log contiene /api/v1: %q", line)
	}
	if !strings.Contains(line, "203.0.113.10") {
		t.Fatalf("log no contiene la IP: %q", line)
	}
	if !strings.Contains(line, "\x1b[") {
		t.Fatalf("log no contiene colores ANSI: %q", line)
	}
	if !strings.Contains(line, "GET") || !strings.Contains(line, "204") {
		t.Fatalf("log no contiene método/status: %q", line)
	}
}
