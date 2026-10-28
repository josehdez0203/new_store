/// Utilidades de formato en español (sin dependencias externas).
String formatDate(DateTime? value) {
  if (value == null) {
    return '—';
  }
  final local = value.toLocal();
  return '${_two(local.day)}/${_two(local.month)}/${local.year}';
}

String formatDateTime(DateTime? value) {
  if (value == null) {
    return '—';
  }
  final local = value.toLocal();
  return '${_two(local.day)}/${_two(local.month)}/${local.year} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

String timeAgo(DateTime? value) {
  if (value == null) {
    return '—';
  }
  final difference = DateTime.now().difference(value.toLocal());
  if (difference.isNegative || difference.inSeconds < 60) {
    return 'Ahora';
  }
  if (difference.inMinutes < 60) {
    return 'Hace ${difference.inMinutes} min';
  }
  if (difference.inHours < 24) {
    return 'Hace ${difference.inHours} h';
  }
  if (difference.inDays < 7) {
    return 'Hace ${difference.inDays} d';
  }
  return formatDate(value);
}

String greetingFor(DateTime now) {
  if (now.hour < 12) {
    return 'Buenos días';
  }
  if (now.hour < 19) {
    return 'Buenas tardes';
  }
  return 'Buenas noches';
}

String roleLabel(String role) {
  return switch (role) {
    'admin' => 'Administrador',
    'vendedor' => 'Vendedor',
    'cobrador' => 'Cobrador',
    'supervisor' => 'Supervisor',
    _ => _capitalize(role),
  };
}

/// Formatea un monto con separador de miles y dos decimales.
String formatMoney(num value) {
  final negative = value < 0;
  final parts = value.abs().toStringAsFixed(2).split('.');
  final integer = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => ',',
  );
  return '${negative ? '-' : ''}\$$integer.${parts[1]}';
}

String _capitalize(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value[0].toUpperCase() + value.substring(1);
}

String _two(int value) => value.toString().padLeft(2, '0');
