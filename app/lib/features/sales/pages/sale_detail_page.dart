import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/sale.dart';
import '../services/sale_export.dart';
import 'sale_form_page.dart';

class SaleDetailPage extends StatefulWidget {
  const SaleDetailPage({super.key, required this.saleId});

  final String saleId;

  @override
  State<SaleDetailPage> createState() => _SaleDetailPageState();
}

class _SaleDetailPageState extends State<SaleDetailPage> {
  Sale? _sale;
  bool _loading = true;
  String? _error;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final result = await api.get('/sales/${widget.saleId}');
      if (!mounted) {
        return;
      }
      setState(() {
        _sale = Sale.fromJson(result.data as Map<String, dynamic>);
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
        _error = 'No se pudo cargar la venta.';
      });
    }
  }

  Future<void> _editSale() async {
    final sale = _sale;
    if (sale == null || _working || sale.isCanceled) {
      return;
    }
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => SaleFormPage(sale: sale)),
    );
    if (updated == true && mounted) {
      await _load();
    }
  }

  Future<void> _confirmSale() async {
    final sale = _sale;
    if (sale == null || _working) {
      return;
    }
    setState(() => _working = true);
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await api.patch(
        '/sales/${sale.id}/status',
        body: {'status': SaleStatuses.sale},
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _sale = Sale.fromJson(result.data as Map<String, dynamic>);
        _working = false;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('La cotización se confirmó como venta.')),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _working = false);
      messenger.showSnackBar(SnackBar(content: Text(error.displayMessage)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _working = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo actualizar la venta.')),
      );
    }
  }

  Future<void> _cancelSale() async {
    final sale = _sale;
    if (sale == null || _working) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancelar venta'),
        content: Text(
          '¿Cancelar ${sale.saleNumber}? La venta quedará marcada como cancelada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancelar venta'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _working = true);
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await api.post('/sales/${sale.id}/cancel');
      if (!mounted) {
        return;
      }
      setState(() {
        _sale = Sale.fromJson(result.data as Map<String, dynamic>);
        _working = false;
      });
      messenger.showSnackBar(const SnackBar(content: Text('Venta cancelada.')));
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _working = false);
      messenger.showSnackBar(SnackBar(content: Text(error.displayMessage)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _working = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo cancelar la venta.')),
      );
    }
  }

  Future<void> _sharePdf() async {
    final sale = _sale;
    if (sale == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SaleExport.sharePdf(sale);
    } catch (_) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo generar el PDF.')),
      );
    }
  }

  Future<void> _sendEmail() async {
    final sale = _sale;
    if (sale == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opened = await SaleExport.sendEmail(sale);
      if (!opened) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el correo.')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el correo.')),
      );
    }
  }

  Future<void> _sendWhatsApp() async {
    final sale = _sale;
    if (sale == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opened = await SaleExport.sendWhatsApp(sale);
      if (!opened) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp.')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo abrir WhatsApp.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>().user;
    final canUpdate = auth?.hasPermission('sales.update') ?? false;
    final canCancel = auth?.hasPermission('sales.cancel') ?? false;
    final sale = _sale;

    return Scaffold(
      appBar: AppBar(
        title: Text(sale == null ? 'Venta' : sale.saleNumber),
        actions: [
          if (sale != null)
            PopupMenuButton<String>(
              tooltip: 'Exportar',
              icon: const Icon(Icons.ios_share_rounded),
              onSelected: (value) {
                if (value == 'pdf') {
                  _sharePdf();
                } else if (value == 'email') {
                  _sendEmail();
                } else if (value == 'whatsapp') {
                  _sendWhatsApp();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'pdf',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.picture_as_pdf_outlined),
                    title: Text('Exportar PDF'),
                  ),
                ),
                PopupMenuItem(
                  value: 'email',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.email_outlined),
                    title: Text('Enviar por correo'),
                  ),
                ),
                PopupMenuItem(
                  value: 'whatsapp',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.chat_outlined),
                    title: Text('Enviar por WhatsApp'),
                  ),
                ),
              ],
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorState(message: _error!, onRetry: _load)
          : sale == null
          ? const SizedBox.shrink()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _HeaderCard(sale: sale),
                          const SizedBox(height: 14),
                          _SectionCard(
                            title: 'Productos',
                            icon: Icons.inventory_2_outlined,
                            child: _ItemsTable(sale: sale),
                          ),
                          const SizedBox(height: 14),
                          _SectionCard(
                            title: 'Plan de pagos',
                            icon: Icons.event_note_outlined,
                            child: _PaymentPlan(sale: sale),
                          ),
                          if (sale.isCredit) ...[
                            const SizedBox(height: 14),
                            _SectionCard(
                              title: 'Resumen del crédito',
                              icon: Icons.credit_score_outlined,
                              child: _CreditSummary(sale: sale),
                            ),
                          ],
                          const SizedBox(height: 14),
                          _ExportActions(
                            onPdf: _sharePdf,
                            onEmail: _sendEmail,
                            onWhatsApp: _sendWhatsApp,
                          ),
                          if ((sale.isQuote && canUpdate) ||
                              (!sale.isCanceled && canCancel)) ...[
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                if (!sale.isCanceled && canUpdate)
                                  OutlinedButton.icon(
                                    onPressed: _working ? null : _editSale,
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Editar venta'),
                                  ),
                                if (sale.isQuote && canUpdate)
                                  FilledButton.icon(
                                    onPressed: _working ? null : _confirmSale,
                                    icon: const Icon(
                                      Icons.check_circle_outline_rounded,
                                    ),
                                    label: const Text('Confirmar venta'),
                                  ),
                                if (!sale.isCanceled && canCancel)
                                  OutlinedButton.icon(
                                    onPressed: _working ? null : _cancelSale,
                                    icon: const Icon(Icons.cancel_outlined),
                                    label: const Text('Cancelar venta'),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sale.clientName,
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${sale.saleNumber} · ${formatDate(sale.saleDate)}',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _SaleStatusBadge(status: sale.status),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _Meta(
                  icon: Icons.badge_outlined,
                  label: 'Vendedor',
                  value: sale.sellerName,
                ),
                _Meta(
                  icon: Icons.payments_outlined,
                  label: 'Forma de pago',
                  value: PaymentTypes.label(sale.paymentType),
                ),
                _Meta(
                  icon: Icons.phone_outlined,
                  label: 'Teléfono',
                  value: sale.clientPhone ?? '—',
                ),
                _Meta(
                  icon: Icons.alternate_email_rounded,
                  label: 'Correo',
                  value: sale.clientEmail ?? '—',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total de la venta', style: textTheme.bodySmall),
                Text(
                  formatMoney(sale.total),
                  style: textTheme.headlineSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 5),
        Text(
          '$label: ',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _ItemsTable extends StatelessWidget {
  const _ItemsTable({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 24,
        headingRowHeight: 34,
        dataRowMinHeight: 38,
        dataRowMaxHeight: 50,
        headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        columns: const [
          DataColumn(label: Text('Producto')),
          DataColumn(label: Text('Cantidad')),
          DataColumn(label: Text('Precio')),
          DataColumn(label: Text('Subtotal')),
        ],
        rows: [
          for (final item in sale.items)
            DataRow(
              cells: [
                DataCell(
                  SizedBox(
                    width: 260,
                    child: Text(item.productName, style: textTheme.bodyMedium),
                  ),
                ),
                DataCell(Text('${item.quantity}')),
                DataCell(Text(formatMoney(item.unitPrice))),
                DataCell(
                  Text(
                    formatMoney(item.subtotal),
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PaymentPlan extends StatelessWidget {
  const _PaymentPlan({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (sale.payments.isEmpty) {
      return const Text('Esta venta todavía no tiene plan de pagos.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 24,
            headingRowHeight: 34,
            dataRowMinHeight: 38,
            dataRowMaxHeight: 50,
            headingRowColor: WidgetStatePropertyAll(
              scheme.surfaceContainerHigh,
            ),
            columns: const [
              DataColumn(label: Text('Concepto')),
              DataColumn(label: Text('Vence')),
              DataColumn(label: Text('Monto')),
            ],
            rows: [
              for (final payment in sale.payments)
                DataRow(
                  cells: [
                    DataCell(
                      Text(
                        payment.kind == 'mensualidad'
                            ? 'Mensualidad ${payment.installmentNumber}'
                            : payment.kindLabel,
                      ),
                    ),
                    DataCell(Text(formatDate(payment.dueDate))),
                    DataCell(
                      Text(
                        formatMoney(payment.amount),
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            'Plan de ${sale.payments.length} pago(s)',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _CreditSummary extends StatelessWidget {
  const _CreditSummary({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        _SummaryRow(
          label: 'Anticipo (${_percent(sale.downPaymentPercent)}%)',
          value: sale.downPayment,
        ),
        _SummaryRow(label: 'Saldo financiado', value: sale.financedAmount),
        _SummaryRow(
          label:
              'Interés (${_percent(sale.monthlyInterestRate)}% mensual · '
              '${sale.months} meses)',
          value: sale.totalInterest,
        ),
        const Divider(),
        _SummaryRow(
          label: 'Total a pagar',
          value: sale.totalWithInterest,
          emphasize: true,
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'El anticipo se paga al registrar la venta; '
            'las mensualidades se generan mes a mes.',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  static String _percent(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
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
          Expanded(
            child: Text(
              label,
              style: emphasize
                  ? textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)
                  : textTheme.bodySmall,
            ),
          ),
          Text(
            formatMoney(value),
            style: emphasize
                ? textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)
                : textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ExportActions extends StatelessWidget {
  const _ExportActions({
    required this.onPdf,
    required this.onEmail,
    required this.onWhatsApp,
  });

  final VoidCallback onPdf;
  final VoidCallback onEmail;
  final VoidCallback onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Compartir plan de pagos',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              'Exporta el detalle con anticipo, intereses y mensualidades.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: onPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: onEmail,
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Correo'),
                ),
                OutlinedButton.icon(
                  onPressed: onWhatsApp,
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('WhatsApp'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SaleStatusBadge extends StatelessWidget {
  const _SaleStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (status) {
      SaleStatuses.quote => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      SaleStatuses.sale => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      SaleStatuses.canceled => (scheme.errorContainer, scheme.onErrorContainer),
      _ => (scheme.surfaceContainerHigh, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        SaleStatuses.label(status),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

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
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
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
