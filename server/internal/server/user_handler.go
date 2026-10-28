package server

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/jhc/credit-store/server/internal/apperr"
	"github.com/jhc/credit-store/server/internal/users"
)

type createUserRequest struct {
	Email    string   `json:"email" binding:"required,email,max=254"`
	FullName string   `json:"full_name" binding:"required,min=2,max=120"`
	Password string   `json:"password" binding:"required,min=6,max=72"`
	IsActive *bool    `json:"is_active"`
	RoleIDs  []string `json:"role_ids" binding:"max=20,dive,uuid"`
}

type updateUserRequest struct {
	FullName *string   `json:"full_name" binding:"omitempty,min=2,max=120"`
	Email    *string   `json:"email" binding:"omitempty,email,max=254"`
	IsActive *bool     `json:"is_active"`
	Password *string   `json:"password" binding:"omitempty,min=6,max=72"`
	RoleIDs  *[]string `json:"role_ids"`
}

type setRolesRequest struct {
	RoleIDs *[]string `json:"role_ids" binding:"required"`
}

type resetPasswordRequest struct {
	Password string `json:"password" binding:"required,min=6,max=72"`
}

func (a *API) listUsers(c *gin.Context) {
	page, pageSize, ok := a.pagination(c)
	if !ok {
		return
	}
	isActive, ok := a.optionalBoolQuery(c, "is_active")
	if !ok {
		return
	}

	items, total, err := a.services.Users.List(c.Request.Context(), users.ListFilter{
		Search:   strings.TrimSpace(c.Query("search")),
		IsActive: isActive,
		Role:     strings.TrimSpace(c.Query("role")),
		Page:     page,
		PageSize: pageSize,
	})
	if err != nil {
		a.fail(c, err)
		return
	}

	respondList(c, usersToResponse(items), pageMeta{
		Page:       page,
		PageSize:   pageSize,
		Total:      total,
		TotalPages: totalPages(total, pageSize),
	})
}

func (a *API) getUser(c *gin.Context) {
	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}

	user, err := a.services.Users.Get(c.Request.Context(), id)
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, userToResponse(user))
}

func (a *API) createUser(c *gin.Context) {
	authCtx, ok := a.requireAuth(c)
	if !ok {
		return
	}

	var req createUserRequest
	if !a.bindJSON(c, &req) {
		return
	}

	roleIDs, err := parseUUIDList("role_ids", req.RoleIDs)
	if err != nil {
		a.fail(c, err)
		return
	}

	isActive := true
	if req.IsActive != nil {
		isActive = *req.IsActive
	}

	user, err := a.services.Users.Create(c.Request.Context(), users.CreateInput{
		Email:    req.Email,
		FullName: req.FullName,
		Password: req.Password,
		IsActive: isActive,
		RoleIDs:  roleIDs,
	}, authCtx.User.ID)
	if err != nil {
		a.fail(c, err)
		return
	}

	respond(c, http.StatusCreated, userToResponse(user))
}

func (a *API) updateUser(c *gin.Context) {
	authCtx, ok := a.requireAuth(c)
	if !ok {
		return
	}

	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}

	var req updateUserRequest
	if !a.bindJSON(c, &req) {
		return
	}
	if req.FullName == nil && req.Email == nil && req.IsActive == nil && req.Password == nil && req.RoleIDs == nil {
		a.fail(c, apperr.Validation("Debes enviar al menos un campo para actualizar.", nil))
		return
	}

	var roleIDs *[]uuid.UUID
	if req.RoleIDs != nil {
		parsed, err := parseUUIDList("role_ids", *req.RoleIDs)
		if err != nil {
			a.fail(c, err)
			return
		}
		roleIDs = &parsed
	}

	user, err := a.services.Users.Update(c.Request.Context(), id, users.UpdateInput{
		FullName: req.FullName,
		Email:    req.Email,
		IsActive: req.IsActive,
		Password: req.Password,
		RoleIDs:  roleIDs,
	}, authCtx.User.ID)
	if err != nil {
		a.fail(c, err)
		return
	}

	respond(c, http.StatusOK, userToResponse(user))
}

func (a *API) deleteUser(c *gin.Context) {
	authCtx, ok := a.requireAuth(c)
	if !ok {
		return
	}

	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}

	if err := a.services.Users.Delete(c.Request.Context(), id, authCtx.User.ID); err != nil {
		a.fail(c, err)
		return
	}
	noContent(c)
}

func (a *API) setUserRoles(c *gin.Context) {
	authCtx, ok := a.requireAuth(c)
	if !ok {
		return
	}

	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}

	var req setRolesRequest
	if !a.bindJSON(c, &req) {
		return
	}

	roleIDs, err := parseUUIDList("role_ids", *req.RoleIDs)
	if err != nil {
		a.fail(c, err)
		return
	}

	user, err := a.services.Users.SetRoles(c.Request.Context(), id, roleIDs, authCtx.User.ID)
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, userToResponse(user))
}

func (a *API) resetUserPassword(c *gin.Context) {
	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}

	var req resetPasswordRequest
	if !a.bindJSON(c, &req) {
		return
	}

	if err := a.services.Users.ResetPassword(c.Request.Context(), id, req.Password); err != nil {
		a.fail(c, err)
		return
	}
	noContent(c)
}
