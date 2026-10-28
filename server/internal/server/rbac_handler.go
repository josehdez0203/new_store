package server

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/jhc/credit-store/server/internal/rbac"
)

type createRoleRequest struct {
	Name          string   `json:"name" binding:"required,min=3,max=50"`
	Description   *string  `json:"description" binding:"omitempty,max=255"`
	PermissionIDs []string `json:"permission_ids" binding:"max=100,dive,uuid"`
}

type updateRoleRequest struct {
	Name        string  `json:"name" binding:"required,min=3,max=50"`
	Description *string `json:"description" binding:"omitempty,max=255"`
}

type setRolePermissionsRequest struct {
	PermissionIDs *[]string `json:"permission_ids" binding:"required"`
}

type permissionRequest struct {
	Name        string  `json:"name" binding:"required,min=3,max=100"`
	Description *string `json:"description" binding:"omitempty,max=255"`
	Module      string  `json:"module" binding:"omitempty,min=2,max=40"`
}

func (a *API) listRoles(c *gin.Context) {
	roles, err := a.services.RBAC.ListRoles(c.Request.Context())
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, rolesToResponse(roles))
}

func (a *API) getRole(c *gin.Context) {
	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}

	role, err := a.services.RBAC.GetRole(c.Request.Context(), id)
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, roleToResponse(role))
}

func (a *API) createRole(c *gin.Context) {
	var req createRoleRequest
	if !a.bindJSON(c, &req) {
		return
	}

	permissionIDs, err := parseUUIDList("permission_ids", req.PermissionIDs)
	if err != nil {
		a.fail(c, err)
		return
	}

	role, err := a.services.RBAC.CreateRole(c.Request.Context(), rbac.RoleInput{
		Name:          req.Name,
		Description:   req.Description,
		PermissionIDs: permissionIDs,
	})
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusCreated, roleToResponse(role))
}

func (a *API) updateRole(c *gin.Context) {
	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}

	var req updateRoleRequest
	if !a.bindJSON(c, &req) {
		return
	}

	role, err := a.services.RBAC.UpdateRole(c.Request.Context(), id, req.Name, req.Description)
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, roleToResponse(role))
}

func (a *API) deleteRole(c *gin.Context) {
	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}

	if err := a.services.RBAC.DeleteRole(c.Request.Context(), id); err != nil {
		a.fail(c, err)
		return
	}
	noContent(c)
}

func (a *API) setRolePermissions(c *gin.Context) {
	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}

	var req setRolePermissionsRequest
	if !a.bindJSON(c, &req) {
		return
	}

	permissionIDs, err := parseUUIDList("permission_ids", *req.PermissionIDs)
	if err != nil {
		a.fail(c, err)
		return
	}

	role, err := a.services.RBAC.SetRolePermissions(c.Request.Context(), id, permissionIDs)
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, roleToResponse(role))
}

func (a *API) listPermissions(c *gin.Context) {
	permissions, err := a.services.RBAC.ListPermissions(
		c.Request.Context(),
		c.Query("search"),
		c.Query("module"),
	)
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, permissionsToResponse(permissions))
}

func (a *API) getPermission(c *gin.Context) {
	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}

	permission, err := a.services.RBAC.GetPermission(c.Request.Context(), id)
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, permissionToResponse(permission))
}

func (a *API) createPermission(c *gin.Context) {
	var req permissionRequest
	if !a.bindJSON(c, &req) {
		return
	}

	permission, err := a.services.RBAC.CreatePermission(c.Request.Context(), rbac.PermissionInput{
		Name:        req.Name,
		Description: req.Description,
		Module:      req.Module,
	})
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusCreated, permissionToResponse(permission))
}

func (a *API) updatePermission(c *gin.Context) {
	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}

	var req permissionRequest
	if !a.bindJSON(c, &req) {
		return
	}

	permission, err := a.services.RBAC.UpdatePermission(c.Request.Context(), id, rbac.PermissionInput{
		Name:        req.Name,
		Description: req.Description,
		Module:      req.Module,
	})
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, permissionToResponse(permission))
}

func (a *API) deletePermission(c *gin.Context) {
	id, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}

	if err := a.services.RBAC.DeletePermission(c.Request.Context(), id); err != nil {
		a.fail(c, err)
		return
	}
	noContent(c)
}
