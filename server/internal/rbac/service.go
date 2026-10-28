// Package rbac implementa la administración de roles y permisos.
package rbac

import (
	"context"
	"errors"
	"regexp"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/jhc/credit-store/server/internal/apperr"
	"github.com/jhc/credit-store/server/internal/database"
	"github.com/jhc/credit-store/server/internal/database/sqlc"
	"github.com/jhc/credit-store/server/internal/domain"
)

var (
	roleNamePattern       = regexp.MustCompile(`^[a-z][a-z0-9_-]{2,49}$`)
	permissionNamePattern = regexp.MustCompile(`^[a-z][a-z0-9_]*([.][a-z][a-z0-9_]*){0,2}$`)
	modulePattern         = regexp.MustCompile(`^[a-z][a-z0-9_-]{1,39}$`)
)

// Service contiene la lógica de roles y permisos.
type Service struct {
	store *database.Store
}

// NewService construye el servicio RBAC.
func NewService(store *database.Store) *Service {
	return &Service{store: store}
}

// RoleInput son los datos para crear un rol.
type RoleInput struct {
	Name          string
	Description   *string
	PermissionIDs []uuid.UUID
}

// PermissionInput son los datos de un permiso.
type PermissionInput struct {
	Name        string
	Description *string
	Module      string
}

// ListRoles devuelve todos los roles con sus contadores.
func (s *Service) ListRoles(ctx context.Context) ([]domain.Role, error) {
	rows, err := s.store.Q.ListRoles(ctx)
	if err != nil {
		return nil, apperr.Internal(err)
	}
	roles := make([]domain.Role, 0, len(rows))
	for _, row := range rows {
		roles = append(roles, roleFromListRow(row))
	}
	return roles, nil
}

// GetRole devuelve un rol con sus permisos.
func (s *Service) GetRole(ctx context.Context, id uuid.UUID) (domain.Role, error) {
	row, err := s.store.Q.GetRoleByID(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Role{}, apperr.NotFound("Rol no encontrado.")
	}
	if err != nil {
		return domain.Role{}, apperr.Internal(err)
	}

	permissions, err := s.store.Q.ListRolePermissions(ctx, id)
	if err != nil {
		return domain.Role{}, apperr.Internal(err)
	}

	role := roleFromGetRow(row)
	role.Permissions = make([]domain.Permission, 0, len(permissions))
	for _, permission := range permissions {
		role.Permissions = append(role.Permissions, permissionFromRoleRow(permission))
	}
	return role, nil
}

// CreateRole crea un rol y le asigna permisos.
func (s *Service) CreateRole(ctx context.Context, in RoleInput) (domain.Role, error) {
	name := normalizeName(in.Name)
	if !roleNamePattern.MatchString(name) {
		return domain.Role{}, validationField("name",
			"El nombre debe iniciar con una letra minúscula y tener entre 3 y 50 caracteres (a-z, 0-9, _ o -).")
	}

	exists, err := s.store.Q.GetRoleByName(ctx, name)
	if err == nil && exists.ID != uuid.Nil {
		return domain.Role{}, apperr.Conflict("Ya existe un rol con ese nombre.")
	}
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return domain.Role{}, apperr.Internal(err)
	}

	permissionIDs, err := s.validatePermissions(ctx, in.PermissionIDs)
	if err != nil {
		return domain.Role{}, err
	}

	description := normalizeDescription(in.Description)
	var roleID uuid.UUID

	err = s.store.WithTx(ctx, func(q *sqlc.Queries) error {
		role, err := q.CreateRole(ctx, sqlc.CreateRoleParams{
			Name:        name,
			Description: description,
			IsSystem:    false,
		})
		if err != nil {
			return err
		}
		roleID = role.ID

		for _, permissionID := range permissionIDs {
			if err := q.AddRolePermission(ctx, sqlc.AddRolePermissionParams{
				RoleID:       role.ID,
				PermissionID: permissionID,
			}); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		if apperr.IsUniqueViolation(err) {
			return domain.Role{}, apperr.Conflict("Ya existe un rol con ese nombre.")
		}
		return domain.Role{}, apperr.Internal(err)
	}

	return s.GetRole(ctx, roleID)
}

// UpdateRole actualiza nombre y descripción. Los permisos se cambian con
// SetRolePermissions.
func (s *Service) UpdateRole(ctx context.Context, id uuid.UUID, name string, description *string) (domain.Role, error) {
	current, err := s.store.Q.GetRoleByID(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Role{}, apperr.NotFound("Rol no encontrado.")
	}
	if err != nil {
		return domain.Role{}, apperr.Internal(err)
	}

	name = normalizeName(name)
	if !roleNamePattern.MatchString(name) {
		return domain.Role{}, validationField("name",
			"El nombre debe iniciar con una letra minúscula y tener entre 3 y 50 caracteres (a-z, 0-9, _ o -).")
	}
	if current.IsSystem && name != current.Name {
		return domain.Role{}, apperr.Conflict("El nombre del rol de sistema no puede modificarse.")
	}

	if _, err := s.store.Q.UpdateRole(ctx, sqlc.UpdateRoleParams{
		ID:          id,
		Name:        name,
		Description: normalizeDescription(description),
	}); err != nil {
		if apperr.IsUniqueViolation(err) {
			return domain.Role{}, apperr.Conflict("Ya existe un rol con ese nombre.")
		}
		return domain.Role{}, apperr.Internal(err)
	}

	return s.GetRole(ctx, id)
}

// DeleteRole elimina un rol si no es de sistema y no tiene usuarios.
func (s *Service) DeleteRole(ctx context.Context, id uuid.UUID) error {
	current, err := s.store.Q.GetRoleByID(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return apperr.NotFound("Rol no encontrado.")
	}
	if err != nil {
		return apperr.Internal(err)
	}
	if current.IsSystem {
		return apperr.Conflict("Los roles de sistema no pueden eliminarse.")
	}
	if current.UserCount > 0 {
		return apperr.Conflict("El rol tiene usuarios asignados. Reasigna esos usuarios antes de eliminarlo.")
	}

	affected, err := s.store.Q.DeleteRole(ctx, id)
	if err != nil {
		return apperr.Internal(err)
	}
	if affected == 0 {
		return apperr.NotFound("Rol no encontrado.")
	}
	return nil
}

// SetRolePermissions reemplaza el conjunto completo de permisos del rol.
func (s *Service) SetRolePermissions(ctx context.Context, id uuid.UUID, permissionIDs []uuid.UUID) (domain.Role, error) {
	if _, err := s.store.Q.GetRoleByID(ctx, id); errors.Is(err, pgx.ErrNoRows) {
		return domain.Role{}, apperr.NotFound("Rol no encontrado.")
	} else if err != nil {
		return domain.Role{}, apperr.Internal(err)
	}

	validIDs, err := s.validatePermissions(ctx, permissionIDs)
	if err != nil {
		return domain.Role{}, err
	}

	err = s.store.WithTx(ctx, func(q *sqlc.Queries) error {
		if err := q.DeleteRolePermissions(ctx, id); err != nil {
			return err
		}
		for _, permissionID := range validIDs {
			if err := q.AddRolePermission(ctx, sqlc.AddRolePermissionParams{
				RoleID:       id,
				PermissionID: permissionID,
			}); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return domain.Role{}, apperr.Internal(err)
	}

	return s.GetRole(ctx, id)
}

// ListPermissions devuelve el catálogo de permisos con filtros opcionales.
func (s *Service) ListPermissions(ctx context.Context, search, module string) ([]domain.Permission, error) {
	search = strings.TrimSpace(search)
	module = strings.ToLower(strings.TrimSpace(module))

	rows, err := s.store.Q.ListPermissions(ctx, sqlc.ListPermissionsParams{
		Module: optionalString(module),
		Search: optionalString(search),
	})
	if err != nil {
		return nil, apperr.Internal(err)
	}

	permissions := make([]domain.Permission, 0, len(rows))
	for _, row := range rows {
		permissions = append(permissions, permissionFromListRow(row))
	}
	return permissions, nil
}

// GetPermission devuelve un permiso por ID.
func (s *Service) GetPermission(ctx context.Context, id uuid.UUID) (domain.Permission, error) {
	row, err := s.store.Q.GetPermissionByID(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Permission{}, apperr.NotFound("Permiso no encontrado.")
	}
	if err != nil {
		return domain.Permission{}, apperr.Internal(err)
	}
	return permissionFromGetRow(row), nil
}

// CreatePermission agrega un permiso al catálogo.
func (s *Service) CreatePermission(ctx context.Context, in PermissionInput) (domain.Permission, error) {
	name := normalizeName(in.Name)
	module := normalizeModule(in.Module)
	if !permissionNamePattern.MatchString(name) {
		return domain.Permission{}, validationField("name",
			"El permiso debe tener un formato como modulo.accion (minúsculas, puntos y guiones bajos).")
	}
	if !modulePattern.MatchString(module) {
		return domain.Permission{}, validationField("module",
			"El módulo debe iniciar con una letra minúscula y tener entre 2 y 40 caracteres.")
	}

	_, err := s.store.Q.GetPermissionByName(ctx, name)
	if err == nil {
		return domain.Permission{}, apperr.Conflict("Ya existe un permiso con ese nombre.")
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return domain.Permission{}, apperr.Internal(err)
	}

	permission, err := s.store.Q.CreatePermission(ctx, sqlc.CreatePermissionParams{
		Name:        name,
		Description: normalizeDescription(in.Description),
		Module:      module,
	})
	if err != nil {
		if apperr.IsUniqueViolation(err) {
			return domain.Permission{}, apperr.Conflict("Ya existe un permiso con ese nombre.")
		}
		return domain.Permission{}, apperr.Internal(err)
	}

	return s.GetPermission(ctx, permission.ID)
}

// UpdatePermission actualiza un permiso existente.
func (s *Service) UpdatePermission(ctx context.Context, id uuid.UUID, in PermissionInput) (domain.Permission, error) {
	if _, err := s.store.Q.GetPermissionByID(ctx, id); errors.Is(err, pgx.ErrNoRows) {
		return domain.Permission{}, apperr.NotFound("Permiso no encontrado.")
	} else if err != nil {
		return domain.Permission{}, apperr.Internal(err)
	}

	name := normalizeName(in.Name)
	module := normalizeModule(in.Module)
	if !permissionNamePattern.MatchString(name) {
		return domain.Permission{}, validationField("name",
			"El permiso debe tener un formato como modulo.accion (minúsculas, puntos y guiones bajos).")
	}
	if !modulePattern.MatchString(module) {
		return domain.Permission{}, validationField("module",
			"El módulo debe iniciar con una letra minúscula y tener entre 2 y 40 caracteres.")
	}

	if _, err := s.store.Q.UpdatePermission(ctx, sqlc.UpdatePermissionParams{
		ID:          id,
		Name:        name,
		Description: normalizeDescription(in.Description),
		Module:      module,
	}); err != nil {
		if apperr.IsUniqueViolation(err) {
			return domain.Permission{}, apperr.Conflict("Ya existe un permiso con ese nombre.")
		}
		return domain.Permission{}, apperr.Internal(err)
	}

	return s.GetPermission(ctx, id)
}

// DeletePermission elimina un permiso si no está asignado a ningún rol.
func (s *Service) DeletePermission(ctx context.Context, id uuid.UUID) error {
	current, err := s.store.Q.GetPermissionByID(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return apperr.NotFound("Permiso no encontrado.")
	}
	if err != nil {
		return apperr.Internal(err)
	}
	if current.RoleCount > 0 {
		return apperr.Conflict("El permiso está asignado a uno o más roles. Quita la asignación antes de eliminarlo.")
	}

	affected, err := s.store.Q.DeletePermission(ctx, id)
	if err != nil {
		return apperr.Internal(err)
	}
	if affected == 0 {
		return apperr.NotFound("Permiso no encontrado.")
	}
	return nil
}

func (s *Service) validatePermissions(ctx context.Context, ids []uuid.UUID) ([]uuid.UUID, error) {
	valid := make([]uuid.UUID, 0, len(ids))
	seen := make(map[uuid.UUID]struct{}, len(ids))

	for _, id := range ids {
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}

		if _, err := s.store.Q.GetPermissionByID(ctx, id); errors.Is(err, pgx.ErrNoRows) {
			return nil, validationField("permission_ids", "Uno o más permisos no existen.")
		} else if err != nil {
			return nil, apperr.Internal(err)
		}
		valid = append(valid, id)
	}
	return valid, nil
}

func roleFromListRow(row sqlc.ListRolesRow) domain.Role {
	return domain.Role{
		ID:              row.ID,
		Name:            row.Name,
		Description:     row.Description,
		IsSystem:        row.IsSystem,
		UserCount:       row.UserCount,
		PermissionCount: row.PermissionCount,
		CreatedAt:       row.CreatedAt,
		UpdatedAt:       row.UpdatedAt,
	}
}

func roleFromGetRow(row sqlc.GetRoleByIDRow) domain.Role {
	return domain.Role{
		ID:              row.ID,
		Name:            row.Name,
		Description:     row.Description,
		IsSystem:        row.IsSystem,
		UserCount:       row.UserCount,
		PermissionCount: row.PermissionCount,
		CreatedAt:       row.CreatedAt,
		UpdatedAt:       row.UpdatedAt,
	}
}

func permissionFromRoleRow(row sqlc.ListRolePermissionsRow) domain.Permission {
	return domain.Permission{
		ID:          row.ID,
		Name:        row.Name,
		Description: row.Description,
		Module:      row.Module,
		RoleCount:   row.RoleCount,
		CreatedAt:   row.CreatedAt,
		UpdatedAt:   row.UpdatedAt,
	}
}

func permissionFromListRow(row sqlc.ListPermissionsRow) domain.Permission {
	return domain.Permission{
		ID:          row.ID,
		Name:        row.Name,
		Description: row.Description,
		Module:      row.Module,
		RoleCount:   row.RoleCount,
		CreatedAt:   row.CreatedAt,
		UpdatedAt:   row.UpdatedAt,
	}
}

func permissionFromGetRow(row sqlc.GetPermissionByIDRow) domain.Permission {
	return domain.Permission{
		ID:          row.ID,
		Name:        row.Name,
		Description: row.Description,
		Module:      row.Module,
		RoleCount:   row.RoleCount,
		CreatedAt:   row.CreatedAt,
		UpdatedAt:   row.UpdatedAt,
	}
}

func normalizeName(value string) string {
	return strings.ToLower(strings.TrimSpace(value))
}

func normalizeModule(value string) string {
	value = normalizeName(value)
	if value == "" {
		return "general"
	}
	return value
}

func normalizeDescription(description *string) *string {
	if description == nil {
		return nil
	}
	value := strings.TrimSpace(*description)
	if value == "" {
		return nil
	}
	return &value
}

func optionalString(value string) *string {
	if value == "" {
		return nil
	}
	return &value
}

func validationField(field, message string) *apperr.Error {
	return apperr.Validation("Datos inválidos.", []apperr.FieldError{{Field: field, Message: message}})
}
