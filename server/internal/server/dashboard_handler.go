package server

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

func (a *API) dashboardStats(c *gin.Context) {
	stats, err := a.services.Dashboard.Stats(c.Request.Context())
	if err != nil {
		a.fail(c, err)
		return
	}
	respond(c, http.StatusOK, dashboardToResponse(stats))
}
