// Package seed carga datos iniciales idempotentes: permisos, roles y usuarios
// de demostración. Se ejecuta al iniciar el API si SEED_ON_START=true.
package seed

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/jhc/credit-store/server/internal/database"
	"github.com/jhc/credit-store/server/internal/database/sqlc"
	"github.com/jhc/credit-store/server/internal/security"
)

type permissionSeed struct {
	Name        string
	Module      string
	Description string
}

type roleSeed struct {
	Name        string
	Description string
	IsSystem    bool
	Permissions []string
}

type userSeed struct {
	Email    string
	FullName string
	Role     string
}

var permissionSeeds = []permissionSeed{
	// Panel
	{Name: "dashboard.read", Module: "dashboard", Description: "Ver el panel principal"},
	// Usuarios
	{Name: "users.read", Module: "usuarios", Description: "Listar y consultar usuarios"},
	{Name: "users.create", Module: "usuarios", Description: "Crear usuarios"},
	{Name: "users.update", Module: "usuarios", Description: "Actualizar usuarios y restablecer contraseñas"},
	{Name: "users.delete", Module: "usuarios", Description: "Eliminar usuarios"},
	{Name: "users.assign_roles", Module: "usuarios", Description: "Asignar roles a usuarios"},
	// Roles
	{Name: "roles.read", Module: "roles", Description: "Listar y consultar roles"},
	{Name: "roles.create", Module: "roles", Description: "Crear roles"},
	{Name: "roles.update", Module: "roles", Description: "Actualizar roles y sus permisos"},
	{Name: "roles.delete", Module: "roles", Description: "Eliminar roles"},
	// Permisos
	{Name: "permissions.read", Module: "permisos", Description: "Listar y consultar permisos"},
	{Name: "permissions.create", Module: "permisos", Description: "Crear permisos"},
	{Name: "permissions.update", Module: "permisos", Description: "Actualizar permisos"},
	{Name: "permissions.delete", Module: "permisos", Description: "Eliminar permisos"},
	// Productos
	{Name: "products.read", Module: "productos", Description: "Listar y consultar productos y servicios"},
	{Name: "products.view_margin", Module: "productos", Description: "Ver el margen de ganancia de productos"},
	{Name: "products.create", Module: "productos", Description: "Crear productos y servicios"},
	{Name: "products.update", Module: "productos", Description: "Actualizar productos y servicios"},
	{Name: "products.delete", Module: "productos", Description: "Eliminar productos y servicios"},
	{Name: "products.manage_images", Module: "productos", Description: "Agregar, reemplazar y eliminar fotos de productos"},
	// Clientes
	{Name: "customers.read", Module: "clientes", Description: "Listar y consultar clientes"},
	{Name: "customers.create", Module: "clientes", Description: "Crear clientes"},
	{Name: "customers.update", Module: "clientes", Description: "Actualizar clientes"},
	{Name: "customers.delete", Module: "clientes", Description: "Eliminar clientes"},
	// Ventas
	{Name: "sales.read", Module: "ventas", Description: "Listar y consultar ventas"},
	{Name: "sales.create", Module: "ventas", Description: "Registrar ventas"},
	{Name: "sales.update", Module: "ventas", Description: "Actualizar ventas"},
	{Name: "sales.cancel", Module: "ventas", Description: "Anular ventas"},
	{Name: "credit_settings.update", Module: "ventas", Description: "Modificar anticipos, plazos e interés de crédito"},
	// Créditos
	{Name: "credits.read", Module: "creditos", Description: "Listar y consultar créditos"},
	{Name: "credits.create", Module: "creditos", Description: "Registrar créditos"},
	{Name: "credits.approve", Module: "creditos", Description: "Aprobar créditos"},
	// Pagos
	{Name: "payments.read", Module: "pagos", Description: "Listar y consultar pagos"},
	{Name: "payments.create", Module: "pagos", Description: "Registrar pagos"},
	// Reportes y configuración
	{Name: "reports.read", Module: "reportes", Description: "Ver reportes"},
	{Name: "settings.read", Module: "configuracion", Description: "Ver la configuración"},
	{Name: "settings.update", Module: "configuracion", Description: "Actualizar la configuración"},
}

var roleSeeds = []roleSeed{
	{
		Name:        "admin",
		Description: "Acceso total al sistema",
		IsSystem:    true,
		// Al rol admin se le asignan todos los permisos del catálogo.
	},
	{
		Name:        "vendedor",
		Description: "Gestiona clientes y ventas a crédito",
		Permissions: []string{
			"dashboard.read",
			"products.read",
			"customers.read", "customers.create", "customers.update",
			"sales.read", "sales.create", "sales.update",
			"credits.read", "credits.create",
			"reports.read",
		},
	},
	{
		Name:        "cobrador",
		Description: "Gestiona la cobranza y los pagos",
		Permissions: []string{
			"dashboard.read",
			"customers.read",
			"credits.read",
			"payments.read", "payments.create",
			"reports.read",
		},
	},
}

var userSeeds = []userSeed{
	{Email: "admin@gmail.com", FullName: "Administrador del Sistema", Role: "admin"},
	{Email: "vendedor@gmail.com", FullName: "Vendedor Demo", Role: "vendedor"},
	{Email: "cobrador@gmail.com", FullName: "Cobrador Demo", Role: "cobrador"},
}

// Run aplica los datos iniciales. Es idempotente: no duplica registros, no
// restablece contraseñas existentes y solo agrega asignaciones faltantes.
func Run(ctx context.Context, store *database.Store, bcryptCost int, password string, log *slog.Logger) error {
	permissionIDs := make(map[string]uuid.UUID, len(permissionSeeds))
	for _, item := range permissionSeeds {
		permission, err := ensurePermission(ctx, store, item, log)
		if err != nil {
			return err
		}
		permissionIDs[item.Name] = permission.ID
	}

	roleIDs := make(map[string]uuid.UUID, len(roleSeeds))
	for _, item := range roleSeeds {
		role, err := ensureRole(ctx, store, item, log)
		if err != nil {
			return err
		}
		roleIDs[item.Name] = role.ID
	}

	// El rol admin siempre conserva todos los permisos del catálogo, incluidos
	// los creados posteriormente por la API.
	allPermissions, err := store.Q.ListPermissions(ctx, sqlc.ListPermissionsParams{})
	if err != nil {
		return fmt.Errorf("listar permisos para admin: %w", err)
	}
	for _, permission := range allPermissions {
		if err := store.Q.AddRolePermission(ctx, sqlc.AddRolePermissionParams{
			RoleID:       roleIDs["admin"],
			PermissionID: permission.ID,
		}); err != nil {
			return fmt.Errorf("asignar permiso %s a admin: %w", permission.Name, err)
		}
	}

	for _, item := range roleSeeds {
		if item.Name == "admin" {
			continue
		}
		for _, permissionName := range item.Permissions {
			permissionID, ok := permissionIDs[permissionName]
			if !ok {
				return fmt.Errorf("el rol %s referencia un permiso semilla desconocido: %s", item.Name, permissionName)
			}
			if err := store.Q.AddRolePermission(ctx, sqlc.AddRolePermissionParams{
				RoleID:       roleIDs[item.Name],
				PermissionID: permissionID,
			}); err != nil {
				return fmt.Errorf("asignar permiso %s a %s: %w", permissionName, item.Name, err)
			}
		}
	}

	var adminID uuid.UUID
	for index, item := range userSeeds {
		roleID, ok := roleIDs[item.Role]
		if !ok {
			return fmt.Errorf("el usuario semilla %s referencia un rol desconocido: %s", item.Email, item.Role)
		}

		var assignedBy *uuid.UUID
		if index > 0 {
			assignedBy = &adminID
		}

		userID, err := ensureUser(ctx, store, item, roleID, assignedBy, bcryptCost, password, log)
		if err != nil {
			return err
		}
		if index == 0 {
			adminID = userID
		}
	}

	log.Info("datos de prueba listos",
		"users", len(userSeeds),
		"roles", len(roleSeeds),
		"permissions", len(permissionSeeds),
		"admin_email", userSeeds[0].Email,
	)
	return nil
}

func ensurePermission(ctx context.Context, store *database.Store, item permissionSeed, log *slog.Logger) (sqlc.Permission, error) {
	current, err := store.Q.GetPermissionByName(ctx, item.Name)
	if errors.Is(err, pgx.ErrNoRows) {
		created, err := store.Q.CreatePermission(ctx, sqlc.CreatePermissionParams{
			Name:        item.Name,
			Description: stringPtr(item.Description),
			Module:      item.Module,
		})
		if err != nil {
			return sqlc.Permission{}, fmt.Errorf("crear permiso %s: %w", item.Name, err)
		}
		log.Debug("seed: permiso creado", "permission", item.Name)
		return created, nil
	}
	if err != nil {
		return sqlc.Permission{}, fmt.Errorf("buscar permiso %s: %w", item.Name, err)
	}

	if current.Module != item.Module || !sameString(current.Description, item.Description) {
		updated, err := store.Q.UpdatePermission(ctx, sqlc.UpdatePermissionParams{
			ID:          current.ID,
			Name:        item.Name,
			Description: stringPtr(item.Description),
			Module:      item.Module,
		})
		if err != nil {
			return sqlc.Permission{}, fmt.Errorf("actualizar permiso %s: %w", item.Name, err)
		}
		log.Debug("seed: permiso actualizado", "permission", item.Name)
		return updated, nil
	}
	return current, nil
}

func ensureRole(ctx context.Context, store *database.Store, item roleSeed, log *slog.Logger) (sqlc.Role, error) {
	current, err := store.Q.GetRoleByName(ctx, item.Name)
	if errors.Is(err, pgx.ErrNoRows) {
		created, err := store.Q.CreateRole(ctx, sqlc.CreateRoleParams{
			Name:        item.Name,
			Description: stringPtr(item.Description),
			IsSystem:    item.IsSystem,
		})
		if err != nil {
			return sqlc.Role{}, fmt.Errorf("crear rol %s: %w", item.Name, err)
		}
		log.Debug("seed: rol creado", "role", item.Name)
		return created, nil
	}
	if err != nil {
		return sqlc.Role{}, fmt.Errorf("buscar rol %s: %w", item.Name, err)
	}

	if item.IsSystem && !current.IsSystem {
		if err := store.Q.SetRoleSystem(ctx, sqlc.SetRoleSystemParams{
			ID:       current.ID,
			IsSystem: true,
		}); err != nil {
			return sqlc.Role{}, fmt.Errorf("marcar rol %s como sistema: %w", item.Name, err)
		}
		current.IsSystem = true
	}
	return current, nil
}

func ensureUser(
	ctx context.Context,
	store *database.Store,
	item userSeed,
	roleID uuid.UUID,
	assignedBy *uuid.UUID,
	bcryptCost int,
	password string,
	log *slog.Logger,
) (uuid.UUID, error) {
	email := strings.ToLower(strings.TrimSpace(item.Email))

	current, err := store.Q.GetUserByEmail(ctx, email)
	if errors.Is(err, pgx.ErrNoRows) {
		hash, err := security.HashPassword(password, bcryptCost)
		if err != nil {
			return uuid.Nil, fmt.Errorf("hashear contraseña semilla: %w", err)
		}
		created, err := store.Q.CreateUser(ctx, sqlc.CreateUserParams{
			Email:        email,
			PasswordHash: hash,
			FullName:     item.FullName,
			IsActive:     true,
		})
		if err != nil {
			return uuid.Nil, fmt.Errorf("crear usuario %s: %w", email, err)
		}
		if err := store.Q.AddUserRole(ctx, sqlc.AddUserRoleParams{
			UserID:     created.ID,
			RoleID:     roleID,
			AssignedBy: assignedBy,
		}); err != nil {
			return uuid.Nil, fmt.Errorf("asignar rol a %s: %w", email, err)
		}
		log.Info("seed: usuario creado", "email", email, "role", item.Role)
		return created.ID, nil
	}
	if err != nil {
		return uuid.Nil, fmt.Errorf("buscar usuario %s: %w", email, err)
	}

	roles, err := store.Q.ListUserRoles(ctx, current.ID)
	if err != nil {
		return uuid.Nil, fmt.Errorf("listar roles de %s: %w", email, err)
	}
	for _, role := range roles {
		if role.ID == roleID {
			return current.ID, nil
		}
	}
	if err := store.Q.AddUserRole(ctx, sqlc.AddUserRoleParams{
		UserID:     current.ID,
		RoleID:     roleID,
		AssignedBy: assignedBy,
	}); err != nil {
		return uuid.Nil, fmt.Errorf("asignar rol a %s: %w", email, err)
	}
	log.Info("seed: rol asignado a usuario existente", "email", email, "role", item.Role)
	return current.ID, nil
}

func stringPtr(value string) *string {
	if value == "" {
		return nil
	}
	return &value
}

func sameString(current *string, expected string) bool {
	if current == nil {
		return expected == ""
	}
	return *current == expected
}
