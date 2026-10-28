package server

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/jhc/credit-store/server/internal/apperr"
	"github.com/jhc/credit-store/server/internal/auth"
)

type loginRequest struct {
	Email    string `json:"email" binding:"required,email,max=254"`
	Password string `json:"password" binding:"required,max=72"`
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required,max=512"`
}

type updateMeRequest struct {
	FullName *string `json:"full_name" binding:"omitempty,min=2,max=120"`
	Email    *string `json:"email" binding:"omitempty,email,max=254"`
}

type changePasswordRequest struct {
	CurrentPassword string `json:"current_password" binding:"required,max=72"`
	NewPassword     string `json:"new_password" binding:"required,min=6,max=72"`
}

func (a *API) login(c *gin.Context) {
	var req loginRequest
	if !a.bindJSON(c, &req) {
		return
	}

	result, err := a.services.Auth.Login(c.Request.Context(), auth.LoginInput{
		Email:     req.Email,
		Password:  req.Password,
		UserAgent: c.Request.UserAgent(),
		IP:        clientIP(c),
	})
	if err != nil {
		a.fail(c, err)
		return
	}

	respond(c, http.StatusOK, authToResponse(result))
}

func (a *API) refresh(c *gin.Context) {
	var req refreshRequest
	if !a.bindJSON(c, &req) {
		return
	}

	result, err := a.services.Auth.Refresh(
		c.Request.Context(),
		req.RefreshToken,
		c.Request.UserAgent(),
		clientIP(c),
	)
	if err != nil {
		a.fail(c, err)
		return
	}

	respond(c, http.StatusOK, authToResponse(result))
}

func (a *API) logout(c *gin.Context) {
	authCtx, ok := a.requireAuth(c)
	if !ok {
		return
	}
	if err := a.services.Auth.Logout(c.Request.Context(), authCtx.User.ID, authCtx.SessionID); err != nil {
		a.fail(c, err)
		return
	}
	noContent(c)
}

func (a *API) logoutAll(c *gin.Context) {
	authCtx, ok := a.requireAuth(c)
	if !ok {
		return
	}
	if err := a.services.Auth.LogoutAll(c.Request.Context(), authCtx.User.ID); err != nil {
		a.fail(c, err)
		return
	}
	noContent(c)
}

func (a *API) me(c *gin.Context) {
	authCtx, ok := a.requireAuth(c)
	if !ok {
		return
	}
	respond(c, http.StatusOK, userToResponse(authCtx.User))
}

func (a *API) updateMe(c *gin.Context) {
	authCtx, ok := a.requireAuth(c)
	if !ok {
		return
	}

	var req updateMeRequest
	if !a.bindJSON(c, &req) {
		return
	}
	if req.FullName == nil && req.Email == nil {
		a.fail(c, apperr.Validation("No hay campos para actualizar.", nil))
		return
	}

	user, err := a.services.Auth.UpdateProfile(c.Request.Context(), authCtx.User.ID, auth.ProfileInput{
		FullName: req.FullName,
		Email:    req.Email,
	})
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, userToResponse(user))
}

func (a *API) changePassword(c *gin.Context) {
	authCtx, ok := a.requireAuth(c)
	if !ok {
		return
	}

	var req changePasswordRequest
	if !a.bindJSON(c, &req) {
		return
	}

	if err := a.services.Auth.ChangePassword(
		c.Request.Context(),
		authCtx.User.ID,
		authCtx.SessionID,
		req.CurrentPassword,
		req.NewPassword,
	); err != nil {
		a.fail(c, err)
		return
	}
	noContent(c)
}

func (a *API) listSessions(c *gin.Context) {
	authCtx, ok := a.requireAuth(c)
	if !ok {
		return
	}

	sessions, err := a.services.Auth.ListSessions(c.Request.Context(), authCtx.User.ID)
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, sessionsToResponse(sessions, authCtx.SessionID))
}

func (a *API) revokeSession(c *gin.Context) {
	authCtx, ok := a.requireAuth(c)
	if !ok {
		return
	}

	sessionID, ok := a.uuidParam(c, "id")
	if !ok {
		return
	}

	if err := a.services.Auth.RevokeSession(c.Request.Context(), authCtx.User.ID, sessionID); err != nil {
		a.fail(c, err)
		return
	}
	noContent(c)
}
