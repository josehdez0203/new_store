SHELL := /bin/bash
.DEFAULT_GOAL := help

# Carga la configuración local si existe (.env no se versiona).
-include .env

# El proyecto puede vivir fuera de un repositorio Git. Go intenta leer el estado
# de VCS al enlazar y falla con "exit status 128"; se desactiva para dev.
GOFLAGS := $(strip $(GOFLAGS) -buildvcs=false)
export

MIGRATIONS_DIR := db/migrations
DATABASE_URL ?= postgres://credit_store:credit_store@localhost:5433/credit_store?sslmode=disable
.PHONY: help deps up down logs psql migrate-up migrate-down migrate-create migrate-force sqlc run seed air build test vet tidy fmt clean dev e2e e2e-products

help: ## Muestra esta ayuda
	@awk 'BEGIN {FS = ":.*##"; printf "\nUso: make \033[36m<target>\033[0m\n\n"} /^[a-zA-Z_-]+:.*?##/ {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

deps: ## Descarga dependencias de Go
	go mod download

up: ## Levanta Postgres 17 en Docker (puerto 5433)
	docker compose up -d db
	@echo "Esperando a que Postgres esté saludable..."
	@until [ "$$(docker inspect -f '{{.State.Health.Status}}' credit_store_db 2>/dev/null)" = "healthy" ]; do sleep 1; done
	@echo "Postgres listo en localhost:$${POSTGRES_PORT:-5433}"

down: ## Detiene los contenedores (conserva datos)
	docker compose down

logs: ## Sigue los logs de Postgres
	docker compose logs -f db

psql: ## Abre psql dentro del contenedor
	docker compose exec db psql -U $${POSTGRES_USER:-credit_store} -d $${POSTGRES_DB:-credit_store}

migrate-up: ## Aplica todas las migraciones
	migrate -path $(MIGRATIONS_DIR) -database "$(DATABASE_URL)" up

migrate-down: ## Revierte la última migración
	migrate -path $(MIGRATIONS_DIR) -database "$(DATABASE_URL)" down 1

migrate-create: ## Crea una migración: make migrate-create name=add_algo
	@test -n "$(name)" || (echo "Falta name=..." && exit 1)
	migrate create -ext sql -dir $(MIGRATIONS_DIR) -seq $(name)

migrate-force: ## Fuerza la versión: make migrate-force version=1
	@test -n "$(version)" || (echo "Falta version=..." && exit 1)
	migrate -path $(MIGRATIONS_DIR) -database "$(DATABASE_URL)" force $(version)

sqlc: ## Genera código tipado con sqlc
	sqlc generate

run: ## Ejecuta el API (migra y siembra si está configurado)
	go run ./cmd/api

seed: ## Ejecuta las migraciones y los datos de prueba
	go run ./cmd/seed

air: ## Inicia el servidor en modo desarrollo con Air
	air -c .air.toml

build: ## Compila el binario en bin/api
	go build -trimpath -buildvcs=false -o bin/api ./cmd/api

test: ## Ejecuta las pruebas unitarias
	go test ./...

e2e: ## Ejecuta la suite E2E contra el API en ejecución (requiere jq)
	@command -v jq >/dev/null || (echo "Se requiere jq para las pruebas E2E" && exit 1)
	bash scripts/e2e.sh

e2e-products: ## Ejecuta la suite E2E de productos (requiere API en ejecución y jq)
	@command -v jq >/dev/null || (echo "Se requiere jq para las pruebas E2E" && exit 1)
	bash scripts/e2e-products.sh

vet: ## Analiza el código con go vet
	go vet ./...

tidy: ## Limpia y actualiza go.mod/go.sum
	go mod tidy

fmt: ## Formatea el código
	gofmt -w .

dev: up ## Levanta Postgres y el API con recarga en caliente
	air -c .air.toml
