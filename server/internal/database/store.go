package database

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/jhc/credit-store/server/internal/database/sqlc"
)

// Store agrupa el pool y las consultas sqlc, y facilita transacciones.
type Store struct {
	Pool *pgxpool.Pool
	Q    *sqlc.Queries
}

// NewStore construye el store a partir del pool.
func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{
		Pool: pool,
		Q:    sqlc.New(pool),
	}
}

// WithTx ejecuta fn dentro de una transacción. Si fn devuelve error se hace
// rollback; si no, se hace commit.
func (s *Store) WithTx(ctx context.Context, fn func(q *sqlc.Queries) error) error {
	tx, err := s.Pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return err
	}
	defer func() {
		_ = tx.Rollback(ctx)
	}()

	if err := fn(s.Q.WithTx(tx)); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
