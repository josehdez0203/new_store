// Package dashboard expone métricas agregadas para la pantalla de inicio.
package dashboard

import (
	"context"

	"github.com/jhc/credit-store/server/internal/apperr"
	"github.com/jhc/credit-store/server/internal/database"
	"github.com/jhc/credit-store/server/internal/domain"
)

// Service contiene la lógica del panel principal.
type Service struct {
	store *database.Store
}

// NewService construye el servicio del dashboard.
func NewService(store *database.Store) *Service {
	return &Service{store: store}
}

// Stats devuelve las métricas principales del sistema.
func (s *Service) Stats(ctx context.Context) (domain.DashboardStats, error) {
	row, err := s.store.Q.GetDashboardStats(ctx)
	if err != nil {
		return domain.DashboardStats{}, apperr.Internal(err)
	}

	byRole, err := s.store.Q.ListUserCountsByRole(ctx)
	if err != nil {
		return domain.DashboardStats{}, apperr.Internal(err)
	}

	stats := domain.DashboardStats{
		UsersTotal:       row.UsersTotal,
		UsersActive:      row.UsersActive,
		RolesTotal:       row.RolesTotal,
		PermissionsTotal: row.PermissionsTotal,
		ActiveSessions:   row.ActiveSessions,
		UsersByRole:      make([]domain.RoleCount, 0, len(byRole)),
	}
	for _, item := range byRole {
		stats.UsersByRole = append(stats.UsersByRole, domain.RoleCount{
			Role:  item.Role,
			Total: item.Total,
		})
	}
	return stats, nil
}
