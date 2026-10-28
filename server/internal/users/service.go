// Package users implementa el CRUD de usuarios y la asignación de roles.
package users

import (
	"context"
	"errors"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/jhc/credit-store/server/internal/apperr"
	"github.com/jhc/credit-store/server/internal/database"
	"github.com/jhc/credit-store/server/internal/database/sqlc"
	"github.com/jhc/credit-store/server/internal/domain"
	"github.com/jhc/credit-store/server/internal/security"
)

// Service contiene la lógica de administración de usuarios.
type Service struct {
	store      *database.Store
	bcryptCost int
}

// NewService construye el servicio de usuarios.
func NewService(store *database.Store, bcryptCost int) *Service {
	return &Service{store: store, bcryptCost: bcryptCost}
}

// ListFilter son los filtros y la paginación del listado.
type ListFilter struct {
	Search   string
	IsActive *bool
	Role     string
	Page     int
	PageSize int
}

// CreateInput son los datos para crear un usuario.
type CreateInput struct {
	Email    string
	FullName string
	Password string
	IsActive bool
	RoleIDs  []uuid.UUID
}

// UpdateInput son los campos opcionales de actualización.
type UpdateInput struct {
	FullName *string
	Email    *string
	IsActive *bool
	Password *string
	RoleIDs  *[]uuid.UUID
}

type roleRef struct {
	ID   uuid.UUID
	Name string
}

// List devuelve usuarios paginados y el total.
func (s *Service) List(ctx context.Context, filter ListFilter) ([]domain.User, int64, error) {
	if filter.Page < 1 {
		filter.Page = 1
	}
	if filter.PageSize < 1 || filter.PageSize > 100 {
		filter.PageSize = 10
	}

	search := strings.TrimSpace(filter.Search)
	role := strings.ToLower(strings.TrimSpace(filter.Role))
	params := sqlc.ListUsersParams{
		Search:   optionalString(search),
		IsActive: filter.IsActive,
		Role:     optionalString(role),
		Limit:    int32(filter.PageSize),
		Offset:   int32((filter.Page - 1) * filter.PageSize),
	}

	rows, err := s.store.Q.ListUsers(ctx, params)
	if err != nil {
		return nil, 0, apperr.Internal(err)
	}

	total, err := s.store.Q.CountUsers(ctx, sqlc.CountUsersParams{
		Search:   params.Search,
		IsActive: params.IsActive,
		Role:     params.Role,
	})
	if err != nil {
		return nil, 0, apperr.Internal(err)
	}

	items := make([]domain.User, 0, len(rows))
	for _, row := range rows {
		items = append(items, domain.User{
			ID:          row.ID,
			Email:       row.Email,
			FullName:    row.FullName,
			IsActive:    row.IsActive,
			Roles:       nonNil(row.Roles),
			Permissions: []string{},
			LastLoginAt: row.LastLoginAt,
			CreatedAt:   row.CreatedAt,
			UpdatedAt:   row.UpdatedAt,
		})
	}
	return items, total, nil
}

// Get devuelve un usuario con sus roles y permisos.
func (s *Service) Get(ctx context.Context, id uuid.UUID) (domain.User, error) {
	row, err := s.store.Q.GetUserAccess(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.User{}, apperr.NotFound("Usuario no encontrado.")
	}
	if err != nil {
		return domain.User{}, apperr.Internal(err)
	}
	return userFromAccess(row), nil
}

// Create crea un usuario y le asigna los roles indicados.
func (s *Service) Create(ctx context.Context, in CreateInput, actorID uuid.UUID) (domain.User, error) {
	email := normalizeEmail(in.Email)
	fullName := strings.TrimSpace(in.FullName)
	if email == "" || fullName == "" {
		return domain.User{}, apperr.Validation("Datos inválidos.", []apperr.FieldError{
			{Field: "email", Message: "El correo es obligatorio."},
			{Field: "full_name", Message: "El nombre es obligatorio."},
		})
	}

	roles, err := s.validateRoles(ctx, in.RoleIDs)
	if err != nil {
		return domain.User{}, err
	}

	exists, err := s.store.Q.UserEmailExists(ctx, sqlc.UserEmailExistsParams{
		Email: email,
		ID:    uuid.Nil,
	})
	if err != nil {
		return domain.User{}, apperr.Internal(err)
	}
	if exists {
		return domain.User{}, apperr.Conflict("El correo ya está registrado por otro usuario.")
	}

	hash, err := security.HashPassword(in.Password, s.bcryptCost)
	if err != nil {
		return domain.User{}, apperr.Validation("Datos inválidos.", []apperr.FieldError{
			{Field: "password", Message: "La contraseña no es válida."},
		})
	}

	var userID uuid.UUID
	err = s.store.WithTx(ctx, func(q *sqlc.Queries) error {
		created, err := q.CreateUser(ctx, sqlc.CreateUserParams{
			Email:        email,
			PasswordHash: hash,
			FullName:     fullName,
			IsActive:     in.IsActive,
		})
		if err != nil {
			return err
		}
		userID = created.ID

		for _, role := range roles {
			assignedBy := actorID
			if err := q.AddUserRole(ctx, sqlc.AddUserRoleParams{
				UserID:     created.ID,
				RoleID:     role.ID,
				AssignedBy: &assignedBy,
			}); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		if apperr.IsUniqueViolation(err) {
			return domain.User{}, apperr.Conflict("El correo ya está registrado por otro usuario.")
		}
		return domain.User{}, apperr.Internal(err)
	}

	return s.Get(ctx, userID)
}

// Update actualiza los campos indicados y, si viene RoleIDs, reemplaza los roles.
func (s *Service) Update(ctx context.Context, id uuid.UUID, in UpdateInput, actorID uuid.UUID) (domain.User, error) {
	current, err := s.store.Q.GetUserByID(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.User{}, apperr.NotFound("Usuario no encontrado.")
	}
	if err != nil {
		return domain.User{}, apperr.Internal(err)
	}

	if in.IsActive != nil && !*in.IsActive && id == actorID {
		return domain.User{}, apperr.Conflict("No puedes desactivar tu propia cuenta.")
	}

	params := sqlc.UpdateUserParams{ID: id}
	passwordChanged := false

	if in.FullName != nil {
		fullName := strings.TrimSpace(*in.FullName)
		if len(fullName) < 2 {
			return domain.User{}, validationField("full_name", "El nombre debe tener al menos 2 caracteres.")
		}
		params.FullName = &fullName
	}

	if in.Email != nil {
		email := normalizeEmail(*in.Email)
		if email == "" {
			return domain.User{}, validationField("email", "El correo es obligatorio.")
		}
		exists, err := s.store.Q.UserEmailExists(ctx, sqlc.UserEmailExistsParams{
			Email: email,
			ID:    id,
		})
		if err != nil {
			return domain.User{}, apperr.Internal(err)
		}
		if exists {
			return domain.User{}, apperr.Conflict("El correo ya está registrado por otro usuario.")
		}
		params.Email = &email
	}

	if in.IsActive != nil {
		params.IsActive = in.IsActive
	}

	if in.Password != nil {
		hash, err := security.HashPassword(*in.Password, s.bcryptCost)
		if err != nil {
			return domain.User{}, validationField("password", "La contraseña no es válida.")
		}
		params.PasswordHash = &hash
		passwordChanged = true
	}

	var roles []roleRef
	if in.RoleIDs != nil {
		roles, err = s.validateRoles(ctx, *in.RoleIDs)
		if err != nil {
			return domain.User{}, err
		}
		if current.IsActive {
			if err := s.ensureAdminRemains(ctx, id, roles); err != nil {
				return domain.User{}, err
			}
		}
	}

	err = s.store.WithTx(ctx, func(q *sqlc.Queries) error {
		if _, err := q.UpdateUser(ctx, params); err != nil {
			return err
		}
		if in.RoleIDs != nil {
			if err := q.DeleteUserRoles(ctx, id); err != nil {
				return err
			}
			for _, role := range roles {
				assignedBy := actorID
				if err := q.AddUserRole(ctx, sqlc.AddUserRoleParams{
					UserID:     id,
					RoleID:     role.ID,
					AssignedBy: &assignedBy,
				}); err != nil {
					return err
				}
			}
		}
		if passwordChanged {
			if _, err := q.RevokeAllUserSessions(ctx, id); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		if apperr.IsUniqueViolation(err) {
			return domain.User{}, apperr.Conflict("El correo ya está registrado por otro usuario.")
		}
		return domain.User{}, apperr.Internal(err)
	}

	return s.Get(ctx, id)
}

// Delete desactiva lógicamente al usuario y revoca todas sus sesiones.
func (s *Service) Delete(ctx context.Context, id, actorID uuid.UUID) error {
	if id == actorID {
		return apperr.Conflict("No puedes eliminar tu propia cuenta.")
	}

	current, err := s.store.Q.GetUserByID(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return apperr.NotFound("Usuario no encontrado.")
	}
	if err != nil {
		return apperr.Internal(err)
	}

	roles, err := s.store.Q.ListUserRoles(ctx, id)
	if err != nil {
		return apperr.Internal(err)
	}
	if current.IsActive && hasRole(roles, "admin") {
		activeAdmins, err := s.store.Q.CountActiveAdmins(ctx)
		if err != nil {
			return apperr.Internal(err)
		}
		if activeAdmins <= 1 {
			return apperr.Conflict("No puedes eliminar al último administrador activo.")
		}
	}

	err = s.store.WithTx(ctx, func(q *sqlc.Queries) error {
		affected, err := q.SoftDeleteUser(ctx, id)
		if err != nil {
			return err
		}
		if affected == 0 {
			return pgx.ErrNoRows
		}
		if _, err := q.RevokeAllUserSessions(ctx, id); err != nil {
			return err
		}
		return nil
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return apperr.NotFound("Usuario no encontrado.")
	}
	if err != nil {
		return apperr.Internal(err)
	}
	return nil
}

// SetRoles reemplaza los roles de un usuario.
func (s *Service) SetRoles(ctx context.Context, id uuid.UUID, roleIDs []uuid.UUID, actorID uuid.UUID) (domain.User, error) {
	current, err := s.store.Q.GetUserByID(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.User{}, apperr.NotFound("Usuario no encontrado.")
	}
	if err != nil {
		return domain.User{}, apperr.Internal(err)
	}

	roles, err := s.validateRoles(ctx, roleIDs)
	if err != nil {
		return domain.User{}, err
	}
	if current.IsActive {
		if err := s.ensureAdminRemains(ctx, id, roles); err != nil {
			return domain.User{}, err
		}
	}

	err = s.store.WithTx(ctx, func(q *sqlc.Queries) error {
		if err := q.DeleteUserRoles(ctx, id); err != nil {
			return err
		}
		for _, role := range roles {
			assignedBy := actorID
			if err := q.AddUserRole(ctx, sqlc.AddUserRoleParams{
				UserID:     id,
				RoleID:     role.ID,
				AssignedBy: &assignedBy,
			}); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return domain.User{}, apperr.Internal(err)
	}

	return s.Get(ctx, id)
}

// ResetPassword asigna una nueva contraseña y revoca las sesiones del usuario.
func (s *Service) ResetPassword(ctx context.Context, id uuid.UUID, password string) error {
	if _, err := s.store.Q.GetUserByID(ctx, id); errors.Is(err, pgx.ErrNoRows) {
		return apperr.NotFound("Usuario no encontrado.")
	} else if err != nil {
		return apperr.Internal(err)
	}

	hash, err := security.HashPassword(password, s.bcryptCost)
	if err != nil {
		return validationField("password", "La contraseña no es válida.")
	}

	err = s.store.WithTx(ctx, func(q *sqlc.Queries) error {
		if _, err := q.UpdateUser(ctx, sqlc.UpdateUserParams{
			ID:           id,
			PasswordHash: &hash,
		}); err != nil {
			return err
		}
		if _, err := q.RevokeAllUserSessions(ctx, id); err != nil {
			return err
		}
		return nil
	})
	if err != nil {
		return apperr.Internal(err)
	}
	return nil
}

// ensureAdminRemains impide que una operación deje al sistema sin
// administradores activos.
func (s *Service) ensureAdminRemains(ctx context.Context, userID uuid.UUID, newRoles []roleRef) error {
	currentRoles, err := s.store.Q.ListUserRoles(ctx, userID)
	if err != nil {
		return apperr.Internal(err)
	}
	if !hasRole(currentRoles, "admin") || hasRoleRef(newRoles, "admin") {
		return nil
	}

	activeAdmins, err := s.store.Q.CountActiveAdmins(ctx)
	if err != nil {
		return apperr.Internal(err)
	}
	if activeAdmins <= 1 {
		return apperr.Conflict("No puedes quitar el rol admin al último administrador activo.")
	}
	return nil
}

func (s *Service) validateRoles(ctx context.Context, ids []uuid.UUID) ([]roleRef, error) {
	refs := make([]roleRef, 0, len(ids))
	seen := make(map[uuid.UUID]struct{}, len(ids))

	for _, id := range ids {
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}

		role, err := s.store.Q.GetRoleByID(ctx, id)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, validationField("role_ids", "Uno o más roles no existen.")
		}
		if err != nil {
			return nil, apperr.Internal(err)
		}
		refs = append(refs, roleRef{ID: role.ID, Name: role.Name})
	}
	return refs, nil
}

func hasRole(roles []sqlc.Role, name string) bool {
	for _, role := range roles {
		if role.Name == name {
			return true
		}
	}
	return false
}

func hasRoleRef(roles []roleRef, name string) bool {
	for _, role := range roles {
		if role.Name == name {
			return true
		}
	}
	return false
}

func userFromAccess(row sqlc.GetUserAccessRow) domain.User {
	return domain.User{
		ID:          row.ID,
		Email:       row.Email,
		FullName:    row.FullName,
		IsActive:    row.IsActive,
		Roles:       nonNil(row.Roles),
		Permissions: nonNil(row.Permissions),
		LastLoginAt: row.LastLoginAt,
		CreatedAt:   row.CreatedAt,
		UpdatedAt:   row.UpdatedAt,
	}
}

func normalizeEmail(value string) string {
	return strings.ToLower(strings.TrimSpace(value))
}

func optionalString(value string) *string {
	if value == "" {
		return nil
	}
	return &value
}

func nonNil(values []string) []string {
	if values == nil {
		return []string{}
	}
	return values
}

func validationField(field, message string) *apperr.Error {
	return apperr.Validation("Datos inválidos.", []apperr.FieldError{{Field: field, Message: message}})
}
