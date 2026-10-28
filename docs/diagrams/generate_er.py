"""Genera el diagrama ER de CrediStore a partir del esquema documentado.

Uso:
    python3 docs/diagrams/generate_er.py
    rsvg-convert -w 2400 docs/diagrams/database-er.svg -o docs/diagrams/database-er.png
"""

from html import escape
from pathlib import Path

WIDTH, HEIGHT = 1740, 1360
OUTPUT = Path(__file__).with_name("database-er.svg")

TABLES = [
    {
        "title": "users",
        "color": "#1E66F5",
        "x": 40,
        "y": 240,
        "rows": [
            ("id", "UUID · PK"),
            ("email", "CITEXT · UQ"),
            ("password_hash", "TEXT"),
            ("full_name", "TEXT"),
            ("is_active", "BOOL"),
            ("deleted_at", "TIMESTAMPTZ"),
            ("created_at / updated_at", "TIMESTAMPTZ"),
        ],
    },
    {
        "title": "user_roles",
        "color": "#209FB5",
        "x": 390,
        "y": 240,
        "rows": [
            ("user_id", "UUID · PK/FK"),
            ("role_id", "UUID · PK/FK"),
            ("assigned_by", "UUID · FK"),
            ("assigned_at", "TIMESTAMPTZ"),
        ],
    },
    {
        "title": "roles",
        "color": "#8839EF",
        "x": 740,
        "y": 240,
        "rows": [
            ("id", "UUID · PK"),
            ("name", "TEXT · UQ"),
            ("description", "TEXT"),
            ("is_system", "BOOL"),
            ("created_at / updated_at", "TIMESTAMPTZ"),
        ],
    },
    {
        "title": "role_permissions",
        "color": "#179299",
        "x": 1090,
        "y": 240,
        "rows": [
            ("role_id", "UUID · PK/FK"),
            ("permission_id", "UUID · PK/FK"),
            ("created_at", "TIMESTAMPTZ"),
        ],
    },
    {
        "title": "permissions",
        "color": "#40A02B",
        "x": 1440,
        "y": 240,
        "rows": [
            ("id", "UUID · PK"),
            ("name", "TEXT · UQ"),
            ("description", "TEXT"),
            ("module", "TEXT"),
            ("created_at / updated_at", "TIMESTAMPTZ"),
        ],
    },
    {
        "title": "sessions",
        "color": "#E64553",
        "x": 40,
        "y": 600,
        "rows": [
            ("id", "UUID · PK"),
            ("user_id", "UUID · FK"),
            ("refresh_token_hash", "TEXT · UQ"),
            ("expires_at", "TIMESTAMPTZ"),
            ("revoked_at", "TIMESTAMPTZ"),
            ("last_used_at / created_at", "TIMESTAMPTZ"),
        ],
    },
    {
        "title": "customers",
        "color": "#7287FD",
        "x": 390,
        "y": 560,
        "rows": [
            ("id", "UUID · PK"),
            ("name", "TEXT"),
            ("address / city / cp", "TEXT"),
            ("phone / email", "TEXT"),
            ("status", "TEXT"),
            ("created_at / updated_at", "TIMESTAMPTZ"),
            ("deleted_at", "TIMESTAMPTZ"),
        ],
    },
    {
        "title": "products",
        "color": "#FE640B",
        "x": 740,
        "y": 580,
        "rows": [
            ("id", "UUID · PK"),
            ("name", "TEXT"),
            ("barcode", "TEXT · UQ"),
            ("price / cost", "NUMERIC"),
            ("margin", "NUMERIC · GEN"),
            ("type", "TEXT"),
            ("deleted_at", "TIMESTAMPTZ"),
        ],
    },
    {
        "title": "product_images",
        "color": "#04A5E5",
        "x": 1360,
        "y": 580,
        "rows": [
            ("id", "UUID · PK"),
            ("product_id", "UUID · FK"),
            ("file_path", "TEXT · UQ"),
            ("mime_type / size", "TEXT / BIGINT"),
            ("sort_order", "INT"),
            ("created_at", "TIMESTAMPTZ"),
        ],
    },
    {
        "title": "sales",
        "color": "#DF8E1D",
        "x": 40,
        "y": 850,
        "rows": [
            ("id", "UUID · PK"),
            ("sale_number", "TEXT · UQ"),
            ("client_id", "UUID · FK"),
            ("seller_id", "UUID · FK"),
            ("sale_date", "DATE"),
            ("status", "TEXT"),
            ("payment_type", "TEXT"),
            ("down_payment / %", "NUMERIC / DOUBLE"),
            ("financed / interest", "NUMERIC / DOUBLE"),
            ("months", "INT"),
            ("total_interest / total", "NUMERIC"),
            ("created_at / updated_at", "TIMESTAMPTZ"),
        ],
    },
    {
        "title": "sale_items",
        "color": "#EF9F76",
        "x": 390,
        "y": 850,
        "rows": [
            ("id", "UUID · PK"),
            ("sale_id", "UUID · FK"),
            ("product_id", "UUID · FK"),
            ("quantity", "INT"),
            ("unit_price", "NUMERIC"),
            ("subtotal", "NUMERIC · GEN"),
            ("UNIQUE", "sale_id + product_id"),
        ],
    },
    {
        "title": "sale_payments",
        "color": "#E64553",
        "x": 740,
        "y": 850,
        "rows": [
            ("id", "UUID · PK"),
            ("sale_id", "UUID · FK"),
            ("installment_number", "INT"),
            ("kind", "TEXT"),
            ("due_date", "DATE"),
            ("amount", "NUMERIC"),
            ("UNIQUE", "sale_id + install."),
        ],
    },
    {
        "title": "credit_settings",
        "color": "#40A02B",
        "x": 1440,
        "y": 850,
        "rows": [
            ("id", "SMALLINT · PK"),
            ("down_payment_options", "DOUBLE[]"),
            ("credit_months", "INT[]"),
            ("monthly_interest_rate", "DOUBLE"),
            ("updated_by / updated_at", "UUID · TIMESTAMPTZ"),
        ],
    },
]

WIDTH_TABLE = 260
HEADER_HEIGHT = 38
ROW_HEIGHT = 26
FOOTER_HEIGHT = 8

parts: list[str] = []
parts.append(
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" '
    f'viewBox="0 0 {WIDTH} {HEIGHT}">'
)
parts.append(
    """<defs>
  <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5"
          markerWidth="7" markerHeight="7" orient="auto-start-reverse">
    <path d="M 0 0 L 10 5 L 0 10 z" fill="#6C6F85"/>
  </marker>
  <filter id="shadow" x="-10%" y="-10%" width="120%" height="120%">
    <feDropShadow dx="0" dy="8" stdDeviation="12"
                  flood-color="#4C4F69" flood-opacity="0.10"/>
  </filter>
</defs>"""
)
parts.append(f'<rect width="{WIDTH}" height="{HEIGHT}" fill="#F7F8FB"/>')
parts.append('<circle cx="1580" cy="100" r="190" fill="#1E66F5" opacity="0.05"/>')
parts.append('<circle cx="160" cy="830" r="230" fill="#179299" opacity="0.05"/>')
parts.append(
    '<text x="40" y="58" font-family="Arial, Helvetica, sans-serif" '
    'font-size="27" font-weight="800" fill="#1A1B26" letter-spacing="-0.6">'
    "CrediStore · Relaciones de la base de datos</text>"
)
parts.append(
    '<text x="40" y="87" font-family="Arial, Helvetica, sans-serif" '
    'font-size="13" fill="#6C6F85">RBAC, sesiones, catálogo, ventas y crédito · PostgreSQL 17 · '
    'migración 000007_sales</text>'
)
parts.append(
    '<rect x="1490" y="39" width="210" height="28" rx="14" fill="#E6E9EF" '
    'stroke="#CCD0DA"/>'
)
parts.append(
    '<text x="1595" y="58" text-anchor="middle" '
    'font-family="Arial, Helvetica, sans-serif" font-size="11" '
    'font-weight="700" fill="#5C5F77">13 tablas de negocio</text>'
)


def box_height(table: dict) -> int:
    return HEADER_HEIGHT + len(table["rows"]) * ROW_HEIGHT + FOOTER_HEIGHT


def draw_table(table: dict) -> None:
    x, y = table["x"], table["y"]
    height = box_height(table)
    color = table["color"]

    parts.append(
        f'<rect x="{x}" y="{y}" width="{WIDTH_TABLE}" height="{height}" rx="14" '
        'fill="#FFFFFF" stroke="#CCD0DA" stroke-width="1.2" '
        'filter="url(#shadow)"/>'
    )
    parts.append(
        f'<path d="M {x} {y + 14} Q {x} {y} {x + 14} {y} '
        f'H {x + WIDTH_TABLE - 14} Q {x + WIDTH_TABLE} {y} '
        f'{x + WIDTH_TABLE} {y + 14} V {y + HEADER_HEIGHT} H {x} Z" '
        f'fill="{color}"/>'
    )
    parts.append(
        f'<text x="{x + 14}" y="{y + 25}" '
        'font-family="Arial, Helvetica, sans-serif" font-size="14.5" '
        f'font-weight="700" fill="#FFFFFF">{table["title"]}</text>'
    )
    parts.append(
        f'<text x="{x + WIDTH_TABLE - 14}" y="{y + 25}" text-anchor="end" '
        'font-family="Arial, Helvetica, sans-serif" font-size="9.5" '
        'fill="#FFFFFF" opacity="0.75">TABLA</text>'
    )

    for index, (column, datatype) in enumerate(table["rows"]):
        row_y = y + HEADER_HEIGHT + index * ROW_HEIGHT
        parts.append(
            f'<line x1="{x}" y1="{row_y}" x2="{x + WIDTH_TABLE}" y2="{row_y}" '
            'stroke="#CCD0DA" stroke-width="0.6"/>'
        )
        parts.append(
            f'<text x="{x + 14}" y="{row_y + 17}" '
            'font-family="Arial, Helvetica, sans-serif" font-size="12" '
            f'fill="#4C4F69">{escape(column)}</text>'
        )
        parts.append(
            f'<text x="{x + WIDTH_TABLE - 14}" y="{row_y + 17}" '
            'text-anchor="end" font-family="Arial, Helvetica, sans-serif" '
            f'font-size="10.5" fill="#7C7F93">{escape(datatype)}</text>'
        )


def edge(x1: float, y1: float, x2: float, y2: float, dashed: bool = False) -> None:
    style = ' stroke-dasharray="6 5"' if dashed else ""
    parts.append(
        f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" '
        'stroke="#6C6F85" stroke-width="1.7" marker-end="url(#arrow)"'
        f"{style}/>"
    )


def label(
    cx: float,
    cy: float,
    title: str,
    subtitle: str | None = None,
    *,
    anchor: str = "middle",
) -> None:
    width = max(len(title), len(subtitle or "")) * 5.6 + 18
    height = 30 if subtitle else 18
    if anchor == "start":
        x = cx
    elif anchor == "end":
        x = cx - width
    else:
        x = cx - width / 2
    parts.append(
        f'<rect x="{x}" y="{cy - height / 2}" width="{width}" height="{height}" '
        'rx="6" fill="#F7F8FB" stroke="#DCE0E8" stroke-width="0.8"/>'
    )
    if subtitle:
        parts.append(
            f'<text x="{x + width / 2}" y="{cy - 2}" text-anchor="middle" '
            'font-family="Arial, Helvetica, sans-serif" font-size="9.5" '
            f'font-weight="700" fill="#4C4F69">{escape(title)}</text>'
        )
        parts.append(
            f'<text x="{x + width / 2}" y="{cy + 10}" text-anchor="middle" '
            'font-family="Arial, Helvetica, sans-serif" font-size="8.5" '
            f'fill="#7C7F93">{escape(subtitle)}</text>'
        )
    else:
        parts.append(
            f'<text x="{x + width / 2}" y="{cy + 3.5}" text-anchor="middle" '
            'font-family="Arial, Helvetica, sans-serif" font-size="9.5" '
            f'fill="#4C4F69">{escape(title)}</text>'
        )


# Aristas principales
edge(300, 340, 390, 340)
edge(740, 340, 650, 340)
edge(1000, 340, 1090, 340)
edge(1440, 340, 1350, 340)
edge(170, 468, 170, 600)
edge(1000, 680, 1360, 680)
edge(520, 788, 170, 850)
edge(300, 900, 390, 900)
edge(870, 808, 520, 850)

# assigned_by: usuario que asignó el rol (opcional)
parts.append(
    '<path d="M 170 240 C 210 145, 500 145, 540 240" fill="none" '
    'stroke="#6C6F85" stroke-width="1.5" stroke-dasharray="6 5" '
    'marker-end="url(#arrow)"/>'
)

# Cajas encima de las aristas
for table in TABLES:
    draw_table(table)

# Etiquetas de cardinalidad
label(345, 340, "1 : N", "user_id")
label(695, 340, "1 : N", "role_id")
label(1045, 340, "1 : N", "role_id")
label(1395, 340, "1 : N", "permission_id")
label(182, 534, "1 : N · user_id", anchor="start")
label(355, 148, "assigned_by · 0..1 : N")
label(1180, 660, "1 : N", "product_id")
label(345, 810, "1 : N", "client_id")
label(345, 885, "1 : N", "sale_id")
label(690, 820, "1 : N", "product_id")

# Leyenda
parts.append(
    '<text x="1360" y="815" font-family="Arial, Helvetica, sans-serif" '
    'font-size="10.5" fill="#6C6F85">Archivos en DOWNLOADS_DIR · mínimo 3 por producto</text>'
)
parts.append(
    '<text x="40" y="1235" font-family="Arial, Helvetica, sans-serif" '
    'font-size="10.5" fill="#6C6F85">sales → customers/users(vendedor) · '
    'sale_items → sales/products · sale_payments → sales · total por trigger</text>'
)
parts.append(
    '<line x1="40" y1="1255" x2="1700" y2="1255" stroke="#DCE0E8" stroke-width="1"/>'
)
parts.append(
    '<text x="40" y="1280" font-family="Arial, Helvetica, sans-serif" '
    'font-size="10.5" fill="#6C6F85">'
    "PK clave primaria · FK clave foránea · UQ único · 1:N uno a muchos · "
    "las tablas pivote resuelven relaciones N:M</text>"
)
parts.append(
    '<text x="40" y="1298" font-family="Arial, Helvetica, sans-serif" '
    'font-size="10.5" fill="#6C6F85">'
    "FK en pivotes, sesiones y galería: ON DELETE CASCADE · "
    "user_roles.assigned_by: ON DELETE SET NULL · users con soft delete</text>"
)

parts.append("</svg>")
OUTPUT.write_text("\n".join(parts), encoding="utf-8")
print(f"Generado: {OUTPUT}")
