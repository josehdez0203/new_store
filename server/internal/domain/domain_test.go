package domain

import "testing"

func TestAuthContextHasPermission(t *testing.T) {
	ctx := AuthContext{User: User{Permissions: []string{"users.read", "sales.create"}}}
	if !ctx.HasPermission("users.read") {
		t.Fatal("debería tener users.read")
	}
	if ctx.HasPermission("users.delete") {
		t.Fatal("no debería tener users.delete")
	}
}

func TestAuthContextWildcardPermission(t *testing.T) {
	ctx := AuthContext{User: User{Permissions: []string{"*"}}}
	if !ctx.HasPermission("cualquier.cosa") {
		t.Fatal("el comodín * debe conceder cualquier permiso")
	}
}

func TestUserHasRole(t *testing.T) {
	user := User{Roles: []string{"admin", "vendedor"}}
	if !user.HasRole("admin") {
		t.Fatal("debería tener el rol admin")
	}
	if user.HasRole("cobrador") {
		t.Fatal("no debería tener el rol cobrador")
	}
}
