import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/providers/auth_provider.dart';
import '../../customers/models/customer.dart';
import '../../products/models/product.dart';
import '../models/sale.dart';
import 'sale_detail_page.dart';

class SaleFormPage extends StatefulWidget {
  const SaleFormPage({super.key, this.sale});

  final Sale? sale;

  @override
  State<SaleFormPage> createState() => _SaleFormPageState();
}

class _SaleLine {
  _SaleLine() : quantity = TextEditingController(text: '1');

  String? productId;
  final TextEditingController quantity;

  void dispose() => quantity.dispose();
}

class _SellerOption {
  const _SellerOption({required this.id, required this.name});

  final String id;
  final String name;
}

class _SaleFormPageState extends State<SaleFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _lines = <_SaleLine>[];

  List<Customer> _clients = const [];
  List<Product> _products = const [];
  List<_SellerOption> _sellers = const [];
  CreditSettings? _settings;

  String? _clientId;
  String? _sellerId;
  DateTime _saleDate = DateTime.now();
  String _status = SaleStatuses.quote;
  String _paymentType = PaymentTypes.cash;
  double? _downPercent;
  int? _months;

  bool _loading = true;
  String? _error;
  bool _saving = false;

  bool get _isEditing => widget.sale != null;

  @override
  void initState() {
    super.initState();
    if (!_isEditing) {
      _lines.add(_SaleLine());
    }
    _loadData();
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    final auth = context.read<AuthProvider>().user;
    try {
      final clients = await api.get(
        '/customers',
        query: {'page': '1', 'page_size': '100'},
      );
      final products = await api.get(
        '/products',
        query: {'page': '1', 'page_size': '100'},
      );
      final settings = await api.get('/credit-settings');

      List<_SellerOption> sellers = const [];
      if (auth?.hasRole('admin') ?? false) {
        final users = await api.get(
          '/users',
          query: {'role': 'vendedor', 'is_active': 'true', 'page_size': '100'},
        );
        sellers = users.asList
            .map(
              (json) => _SellerOption(
                id: json['id'] as String? ?? '',
                name: (json['full_name'] as String?)?.trim().isNotEmpty ?? false
                    ? json['full_name'] as String
                    : json['email'] as String? ?? 'Vendedor',
              ),
            )
            .where((seller) => seller.id.isNotEmpty)
            .toList(growable: false);
      }

      if (!mounted) {
        return;
      }
      final parsedSettings = CreditSettings.fromJson(
        settings.data as Map<String, dynamic>,
      );
      final parsedClients = clients.asList
          .map(Customer.fromJson)
          .toList(growable: false);
      final parsedProducts = products.asList
          .map(Product.fromJson)
          .toList(growable: false);
      final sale = widget.sale;
      final isAdmin = auth?.hasRole('admin') ?? false;

      if (sale != null) {
        for (final line in _lines) {
          line.dispose();
        }
        _lines.clear();
        for (final item in sale.items) {
          final productExists = parsedProducts.any(
            (product) => product.id == item.productId,
          );
          final line = _SaleLine();
          line.productId = productExists ? item.productId : null;
          line.quantity.text = '${item.quantity}';
          _lines.add(line);
        }
        if (_lines.isEmpty) {
          _lines.add(_SaleLine());
        }
      }

      final clientExists = parsedClients.any(
        (client) => client.id == sale?.clientId,
      );
      final sellerExists = sellers.any((seller) => seller.id == sale?.sellerId);
      final defaultDown = parsedSettings.downPaymentOptions.isNotEmpty
          ? parsedSettings.downPaymentOptions.first
          : null;
      final defaultMonths = parsedSettings.creditMonths.isNotEmpty
          ? parsedSettings.creditMonths.first
          : null;
      final saleDown = sale == null
          ? null
          : (parsedSettings.downPaymentOptions.any(
                  (option) => (option - sale.downPaymentPercent).abs() < 0.001,
                )
                ? sale.downPaymentPercent
                : defaultDown);
      final saleMonths = sale == null
          ? null
          : (parsedSettings.creditMonths.contains(sale.months)
                ? sale.months
                : defaultMonths);

      setState(() {
        _clients = parsedClients;
        _products = parsedProducts;
        _sellers = sellers;
        _settings = parsedSettings;
        _clientId = sale == null
            ? null
            : (clientExists
                  ? sale.clientId
                  : (parsedClients.isNotEmpty ? parsedClients.first.id : null));
        _sellerId = isAdmin
            ? (sale == null
                  ? (sellers.isNotEmpty ? sellers.first.id : null)
                  : (sellerExists
                        ? sale.sellerId
                        : (sellers.isNotEmpty ? sellers.first.id : null)))
            : auth?.id;
        _saleDate = sale?.saleDate ?? DateTime.now();
        _status =
            sale != null && SaleStatuses.createValues.contains(sale.status)
            ? sale.status
            : SaleStatuses.quote;
        _paymentType = sale?.paymentType ?? PaymentTypes.cash;
        _downPercent = sale == null ? defaultDown : saleDown;
        _months = sale == null ? defaultMonths : saleMonths;
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
        _error = 'No se pudieron cargar los datos para la venta.';
      });
    }
  }

  Product? _productById(String? id) {
    if (id == null) {
      return null;
    }
    for (final product in _products) {
      if (product.id == id) {
        return product;
      }
    }
    return null;
  }

  double get _total {
    var total = 0.0;
    for (final line in _lines) {
      final product = _productById(line.productId);
      final quantity = int.tryParse(line.quantity.text) ?? 0;
      if (product != null && quantity > 0) {
        total += product.price * quantity;
      }
    }
    return total;
  }

  double get _downAmount => _total * ((_downPercent ?? 0) / 100);

  double get _financed => _total - _downAmount;

  double get _interest =>
      _financed *
      ((_settings?.monthlyInterestRate ?? 0) / 100) *
      (_months ?? 0);

  double get _totalToPay => _total + _interest;

  double get _monthly =>
      (_months ?? 0) > 0 ? (_totalToPay - _downAmount) / _months! : 0;

  void _setPaymentType(String type) {
    setState(() {
      _paymentType = type;
      if (type == PaymentTypes.credit) {
        if (_downPercent == null &&
            (_settings?.downPaymentOptions.isNotEmpty ?? false)) {
          _downPercent = _settings!.downPaymentOptions.first;
        }
        if (_months == null && (_settings?.creditMonths.isNotEmpty ?? false)) {
          _months = _settings!.creditMonths.first;
        }
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _saleDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035, 12, 31),
      helpText: 'Fecha de la venta',
    );
    if (picked != null && mounted) {
      setState(() => _saleDate = picked);
    }
  }

  void _addLine() {
    setState(() => _lines.add(_SaleLine()));
  }

  void _removeLine(int index) {
    setState(() {
      final line = _lines.removeAt(index);
      line.dispose();
    });
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>().user;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_clientId == null) {
      _showMessage('Selecciona un cliente.');
      return;
    }
    if ((auth?.hasRole('admin') ?? false) && _sellerId == null) {
      _showMessage('Selecciona un vendedor.');
      return;
    }
    if (_lines.isEmpty || _lines.any((line) => line.productId == null)) {
      _showMessage('Agrega al menos un producto.');
      return;
    }
    if (_paymentType == PaymentTypes.credit &&
        (_downPercent == null || _months == null)) {
      _showMessage('Selecciona el anticipo y el plazo.');
      return;
    }

    setState(() => _saving = true);
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final body = <String, dynamic>{
        'client_id': _clientId,
        if (auth?.hasRole('admin') ?? false) 'seller_id': _sellerId,
        'sale_date': _apiDate(_saleDate),
        'status': _status,
        'payment_type': _paymentType,
        'down_payment_percent': _paymentType == PaymentTypes.credit
            ? _downPercent
            : 0,
        'months': _paymentType == PaymentTypes.credit ? _months : 0,
        'items': [
          for (final line in _lines)
            {
              'product_id': line.productId,
              'quantity': int.tryParse(line.quantity.text) ?? 0,
            },
        ],
      };
      final result = _isEditing
          ? await api.put('/sales/${widget.sale!.id}', body: body)
          : await api.post('/sales', body: body);
      if (!mounted) {
        return;
      }
      final sale = Sale.fromJson(result.data as Map<String, dynamic>);
      if (_isEditing) {
        messenger.showSnackBar(
          SnackBar(content: Text('Venta ${sale.saleNumber} actualizada.')),
        );
        Navigator.of(context).pop(true);
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Venta ${sale.saleNumber} creada.')),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SaleDetailPage(saleId: sale.id),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(error.displayMessage)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo registrar la venta.')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
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

  String _apiDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>().user;
    final isAdmin = auth?.hasRole('admin') ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Editar venta' : 'Nueva venta')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorState(message: _error!, onRetry: _loadData)
          : Form(
              key: _formKey,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    children: [
                      _SectionCard(
                        title: 'Datos de la venta',
                        icon: Icons.receipt_long_outlined,
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: _clientId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Cliente *',
                                prefixIcon: Icon(Icons.person_outline_rounded),
                              ),
                              items: [
                                for (final client in _clients)
                                  DropdownMenuItem(
                                    value: client.id,
                                    child: Text(
                                      client.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _clientId = value),
                              validator: (value) => value == null
                                  ? 'Selecciona un cliente.'
                                  : null,
                            ),
                            if (_clients.isEmpty)
                              _InlineHint(
                                text: 'No hay clientes. Crea uno en Clientes.',
                                onAction: null,
                              ),
                            const SizedBox(height: 12),
                            if (isAdmin)
                              DropdownButtonFormField<String>(
                                initialValue: _sellerId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Vendedor *',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                                items: [
                                  for (final seller in _sellers)
                                    DropdownMenuItem(
                                      value: seller.id,
                                      child: Text(
                                        seller.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (value) =>
                                    setState(() => _sellerId = value),
                                validator: (value) => value == null
                                    ? 'Selecciona un vendedor.'
                                    : null,
                              )
                            else
                              InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Vendedor',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                                child: Text(auth?.displayName ?? '—'),
                              ),
                            const SizedBox(height: 12),
                            InkWell(
                              onTap: _pickDate,
                              borderRadius: BorderRadius.circular(12),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Fecha',
                                  prefixIcon: Icon(
                                    Icons.calendar_today_outlined,
                                  ),
                                ),
                                child: Text(formatDate(_saleDate)),
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _status,
                              decoration: const InputDecoration(
                                labelText: 'Estado',
                                prefixIcon: Icon(Icons.flag_outlined),
                              ),
                              items: [
                                for (final status in SaleStatuses.createValues)
                                  DropdownMenuItem(
                                    value: status,
                                    child: Text(SaleStatuses.label(status)),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _status = value);
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _paymentType,
                              decoration: const InputDecoration(
                                labelText: 'Forma de pago',
                                prefixIcon: Icon(Icons.payments_outlined),
                              ),
                              items: [
                                for (final type in [
                                  PaymentTypes.cash,
                                  PaymentTypes.credit,
                                ])
                                  DropdownMenuItem(
                                    value: type,
                                    child: Text(PaymentTypes.label(type)),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  _setPaymentType(value);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: 'Productos',
                        icon: Icons.inventory_2_outlined,
                        trailing: _products.isEmpty
                            ? null
                            : TextButton.icon(
                                onPressed: _addLine,
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('Agregar'),
                              ),
                        child: Column(
                          children: [
                            if (_products.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  'No hay productos disponibles para vender.',
                                ),
                              )
                            else
                              for (
                                var index = 0;
                                index < _lines.length;
                                index++
                              )
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _buildLine(index),
                                ),
                            const Divider(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${_lines.length} partida(s)',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                Text(
                                  formatMoney(_total),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (_paymentType == PaymentTypes.credit) ...[
                        const SizedBox(height: 14),
                        _SectionCard(
                          title: 'Plan de crédito',
                          icon: Icons.credit_score_outlined,
                          child: _buildCreditPlan(),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: 'Resumen',
                        icon: Icons.summarize_outlined,
                        child: Column(
                          children: [
                            _SummaryRow(label: 'Subtotal', value: _total),
                            _SummaryRow(
                              label: 'Anticipo',
                              value: _paymentType == PaymentTypes.credit
                                  ? _downAmount
                                  : 0,
                            ),
                            _SummaryRow(
                              label: 'Interés',
                              value: _paymentType == PaymentTypes.credit
                                  ? _interest
                                  : 0,
                            ),
                            const Divider(),
                            _SummaryRow(
                              label: 'Total a pagar',
                              value: _paymentType == PaymentTypes.credit
                                  ? _totalToPay
                                  : _total,
                              emphasize: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _saving ? null : _submit,
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
                              : (_isEditing
                                    ? 'Guardar cambios'
                                    : 'Registrar venta'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildCreditPlan() {
    final settings = _settings;
    final scheme = Theme.of(context).colorScheme;
    if (settings == null ||
        settings.downPaymentOptions.isEmpty ||
        settings.creditMonths.isEmpty) {
      return Text(
        'La empresa no tiene anticipos o plazos configurados.',
        style: TextStyle(color: scheme.error),
      );
    }
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DropdownButtonFormField<double>(
                initialValue:
                    _containsDouble(settings.downPaymentOptions, _downPercent)
                    ? _downPercent
                    : settings.downPaymentOptions.first,
                decoration: const InputDecoration(
                  labelText: 'Anticipo',
                  prefixIcon: Icon(Icons.percent_rounded),
                ),
                items: [
                  for (final option in settings.downPaymentOptions)
                    DropdownMenuItem(
                      value: option,
                      child: Text('${_formatPercent(option)}%'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _downPercent = value);
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: settings.creditMonths.contains(_months)
                    ? _months
                    : settings.creditMonths.first,
                decoration: const InputDecoration(
                  labelText: 'Meses',
                  prefixIcon: Icon(Icons.event_repeat_rounded),
                ),
                items: [
                  for (final months in settings.creditMonths)
                    DropdownMenuItem(
                      value: months,
                      child: Text('$months meses'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _months = value);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _SummaryRow(label: 'Anticipo', value: _downAmount),
              _SummaryRow(label: 'Saldo financiado', value: _financed),
              _SummaryRow(
                label:
                    'Interés ${_formatPercent(settings.monthlyInterestRate)}% mensual',
                value: _interest,
              ),
              _SummaryRow(label: 'Mensualidad aproximada', value: _monthly),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLine(int index) {
    final line = _lines[index];
    final product = _productById(line.productId);
    final quantity = int.tryParse(line.quantity.text) ?? 0;
    final subtotal = product == null ? 0.0 : product.price * quantity;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: line.productId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Producto',
                    isDense: true,
                  ),
                  items: [
                    for (final product in _products)
                      DropdownMenuItem(
                        value: product.id,
                        child: Text(
                          '${product.name} · ${formatMoney(product.price)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() => line.productId = value);
                  },
                  validator: (value) =>
                      value == null ? 'Selecciona un producto.' : null,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: TextFormField(
                  controller: line.quantity,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Cant.',
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    final parsed = int.tryParse(value ?? '');
                    if (parsed == null || parsed < 1) {
                      return 'Cantidad';
                    }
                    return null;
                  },
                ),
              ),
              IconButton(
                tooltip: 'Quitar',
                onPressed: _lines.length == 1 ? null : () => _removeLine(index),
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                product == null ? 'Selecciona un producto' : product.name,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              Text(
                formatMoney(subtotal),
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static bool _containsDouble(List<double> values, double? value) {
    return value != null && values.any((item) => (item - value).abs() < 0.001);
  }

  static String _formatPercent(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final double value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: emphasize
                ? textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)
                : textTheme.bodySmall,
          ),
          Text(
            formatMoney(value),
            style: emphasize
                ? textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)
                : textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _InlineHint extends StatelessWidget {
  const _InlineHint({required this.text, required this.onAction});

  final String text;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: scheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
          if (onAction != null)
            TextButton(onPressed: onAction, child: const Text('Reintentar')),
        ],
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
