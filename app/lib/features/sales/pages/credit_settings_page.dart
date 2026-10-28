import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/sale.dart';

/// Administración de anticipos, plazos e interés de crédito.
/// Solo accesible con `credit_settings.update`.
class CreditSettingsPage extends StatefulWidget {
  const CreditSettingsPage({super.key});

  @override
  State<CreditSettingsPage> createState() => _CreditSettingsPageState();
}

class _CreditSettingsPageState extends State<CreditSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _downController = TextEditingController();
  final _monthsController = TextEditingController();
  final _interestController = TextEditingController();
  CreditSettings? _settings;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _downController.dispose();
    _monthsController.dispose();
    _interestController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final result = await api.get('/credit-settings');
      if (!mounted) {
        return;
      }
      final settings = CreditSettings.fromJson(
        result.data as Map<String, dynamic>,
      );
      _fill(settings);
      setState(() {
        _settings = settings;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.displayMessage;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar la configuración de crédito.';
      });
    }
  }

  void _fill(CreditSettings settings) {
    _downController.text = settings.downPaymentOptions
        .map(_formatNumber)
        .join(', ');
    _monthsController.text = settings.creditMonths.join(', ');
    _interestController.text = _formatNumber(settings.monthlyInterestRate);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final downs = _parseDoubles(_downController.text);
    final months = _parseInts(_monthsController.text);
    if (!_validDownPayments(downs)) {
      _showMessage(
        'Escribe entre 1 y 10 anticipos, cada uno entre 0 y 99.99%.',
      );
      return;
    }
    if (!_validMonths(months)) {
      _showMessage('Escribe entre 1 y 10 plazos, cada uno entre 1 y 60 meses.');
      return;
    }
    final interest = double.tryParse(_interestController.text.trim());
    if (interest == null || interest < 0 || interest > 100) {
      _showMessage('El interés mensual debe estar entre 0 y 100%.');
      return;
    }

    setState(() => _saving = true);
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await api.put(
        '/credit-settings',
        body: {
          'down_payment_options': downs,
          'credit_months': months,
          'monthly_interest_rate': interest,
        },
      );
      if (!mounted) {
        return;
      }
      final settings = CreditSettings.fromJson(
        result.data as Map<String, dynamic>,
      );
      _fill(settings);
      setState(() {
        _settings = settings;
        _saving = false;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Configuración de crédito actualizada.')),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      _showMessage(error.displayMessage);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      _showMessage('No se pudo guardar la configuración.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>().user;
    final canEdit = auth?.hasPermission('credit_settings.update') ?? false;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración de crédito'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: !canEdit
          ? const _NoAccess()
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorState(message: _error!, onRetry: _load)
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.tune_rounded, color: scheme.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Parámetros de financiamiento',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Estos valores se guardan en la tabla '
                                    'credit_settings y se usan para generar '
                                    'los planes de pago de las ventas a crédito.',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _downController,
                                decoration: const InputDecoration(
                                  labelText: 'Anticipos permitidos (%)',
                                  helperText:
                                      'Lista separada por comas. Ej. 10, 20, 30',
                                  prefixIcon: Icon(Icons.percent_rounded),
                                ),
                                validator: (value) =>
                                    (value ?? '').trim().isEmpty
                                    ? 'Escribe al menos un anticipo.'
                                    : null,
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _monthsController,
                                decoration: const InputDecoration(
                                  labelText: 'Meses de crédito permitidos',
                                  helperText:
                                      'Lista separada por comas. Ej. 3, 6, 12',
                                  prefixIcon: Icon(Icons.event_repeat_rounded),
                                ),
                                validator: (value) =>
                                    (value ?? '').trim().isEmpty
                                    ? 'Escribe al menos un plazo.'
                                    : null,
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _interestController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Interés mensual (%)',
                                  helperText:
                                      'Se aplica al saldo después del anticipo.',
                                  prefixIcon: Icon(Icons.trending_up_rounded),
                                ),
                                validator: (value) {
                                  final parsed = double.tryParse(
                                    (value ?? '').trim(),
                                  );
                                  if (parsed == null ||
                                      parsed < 0 ||
                                      parsed > 100) {
                                    return 'Ingresa un interés entre 0 y 100.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 18),
                              FilledButton.icon(
                                onPressed: _saving ? null : _save,
                                icon: _saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.save_outlined),
                                label: Text(
                                  _saving
                                      ? 'Guardando...'
                                      : 'Guardar configuración',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_settings?.updatedAt != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.history_rounded,
                            size: 15,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Última actualización: '
                            '${formatDateTime(_settings!.updatedAt)}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 17,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Solo el administrador puede modificar estos '
                              'valores. Los cambios aplican a las nuevas ventas.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  static bool _validDownPayments(List<double>? values) {
    return values != null &&
        values.isNotEmpty &&
        values.length <= 10 &&
        values.every((value) => value >= 0 && value < 100);
  }

  static bool _validMonths(List<int>? values) {
    return values != null &&
        values.isNotEmpty &&
        values.length <= 10 &&
        values.every((value) => value >= 1 && value <= 60);
  }

  static String _formatNumber(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  static List<double>? _parseDoubles(String raw) {
    final values = <double>[];
    for (final part in raw.split(RegExp(r'[,;\s]+'))) {
      if (part.trim().isEmpty) {
        continue;
      }
      final parsed = double.tryParse(part.trim());
      if (parsed == null) {
        return null;
      }
      values.add(parsed);
    }
    return values;
  }

  static List<int>? _parseInts(String raw) {
    final values = <int>[];
    for (final part in raw.split(RegExp(r'[,;\s]+'))) {
      if (part.trim().isEmpty) {
        continue;
      }
      final parsed = int.tryParse(part.trim());
      if (parsed == null) {
        return null;
      }
      values.add(parsed);
    }
    return values;
  }
}

class _NoAccess extends StatelessWidget {
  const _NoAccess();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 42),
            const SizedBox(height: 12),
            Text(
              'Esta configuración solo la puede modificar el administrador.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
