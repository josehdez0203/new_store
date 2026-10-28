import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/formatters.dart';
import '../models/sale.dart';

/// Genera y comparte el plan de pagos de una venta.
abstract final class SaleExport {
  static String planText(Sale sale) {
    final buffer = StringBuffer()
      ..writeln('CrediStore · ${sale.saleNumber}')
      ..writeln('Cliente: ${sale.clientName}')
      ..writeln('Vendedor: ${sale.sellerName}')
      ..writeln('Fecha: ${formatDate(sale.saleDate)}')
      ..writeln('Estado: ${SaleStatuses.label(sale.status)}')
      ..writeln('Forma de pago: ${PaymentTypes.label(sale.paymentType)}')
      ..writeln('')
      ..writeln('Productos:');
    for (final item in sale.items) {
      buffer.writeln(
        '· ${item.productName} x${item.quantity} '
        '= ${formatMoney(item.subtotal)}',
      );
    }
    buffer
      ..writeln('')
      ..writeln('Total: ${formatMoney(sale.total)}');
    if (sale.isCredit) {
      buffer
        ..writeln(
          'Anticipo (${sale.downPaymentPercent.toStringAsFixed(2)}%): '
          '${formatMoney(sale.downPayment)}',
        )
        ..writeln('Saldo financiado: ${formatMoney(sale.financedAmount)}')
        ..writeln(
          'Interés (${sale.monthlyInterestRate.toStringAsFixed(2)}% '
          'mensual): ${formatMoney(sale.totalInterest)}',
        )
        ..writeln('Total a pagar: ${formatMoney(sale.totalWithInterest)}')
        ..writeln('')
        ..writeln('Plan de pagos:');
      for (final payment in sale.payments) {
        buffer.writeln(
          '· ${payment.kindLabel} ${payment.installmentNumber}: '
          '${formatDate(payment.dueDate)} · ${formatMoney(payment.amount)}',
        );
      }
    } else {
      for (final payment in sale.payments) {
        buffer.writeln(
          '· ${payment.kindLabel}: ${formatDate(payment.dueDate)} · '
          '${formatMoney(payment.amount)}',
        );
      }
    }
    return buffer.toString().trimRight();
  }

  static Future<void> sharePdf(Sale sale) async {
    final bytes = await buildPdf(sale);
    await Printing.sharePdf(bytes: bytes, filename: '${sale.saleNumber}.pdf');
  }

  static Future<Uint8List> buildPdf(Sale sale) async {
    final document = pw.Document();
    final dark = PdfColor.fromHex('#1E1E2E');
    final accent = PdfColor.fromHex('#7287FD');
    final muted = PdfColor.fromHex('#6C6F85');

    pw.Widget header() {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'CrediStore',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: accent,
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#EEF1FF'),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  SaleStatuses.label(sale.status),
                  style: pw.TextStyle(fontSize: 9, color: accent),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '${sale.saleNumber} · ${formatDate(sale.saleDate)}',
            style: pw.TextStyle(fontSize: 10, color: muted),
          ),
          pw.Divider(color: PdfColor.fromHex('#DCE0E8')),
        ],
      );
    }

    pw.Widget dataRow(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 84,
              child: pw.Text(
                label,
                style: pw.TextStyle(fontSize: 9, color: muted),
              ),
            ),
            pw.Expanded(
              child: pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
            ),
          ],
        ),
      );
    }

    pw.Widget sectionTitle(String title) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 5),
        child: pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: dark,
          ),
        ),
      );
    }

    pw.Widget table(List<String> headers, List<List<String>> rows) {
      return pw.Table(
        border: pw.TableBorder(
          horizontalInside: pw.BorderSide(
            color: PdfColor.fromHex('#DCE0E8'),
            width: 0.5,
          ),
        ),
        columnWidths: {
          for (var index = 0; index < headers.length; index++)
            index: index == 0
                ? const pw.FlexColumnWidth(3)
                : const pw.FlexColumnWidth(1.5),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F2F4F8')),
            children: [
              for (final header in headers)
                pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Text(
                    header,
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: dark,
                    ),
                  ),
                ),
            ],
          ),
          for (final row in rows)
            pw.TableRow(
              children: [
                for (final cell in row)
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(
                      cell,
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ),
              ],
            ),
        ],
      );
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(34),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'CrediStore · Página ${context.pageNumber} de ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 7, color: muted),
          ),
        ),
        build: (context) => [
          header(),
          pw.SizedBox(height: 10),
          dataRow('Cliente', sale.clientName),
          if (sale.clientPhone != null) dataRow('Teléfono', sale.clientPhone!),
          if (sale.clientEmail != null) dataRow('Correo', sale.clientEmail!),
          dataRow('Vendedor', sale.sellerName),
          dataRow('Pago', PaymentTypes.label(sale.paymentType)),
          if (sale.isCredit)
            dataRow(
              'Anticipo',
              '${sale.downPaymentPercent.toStringAsFixed(2)}% · '
                  '${formatMoney(sale.downPayment)}',
            ),
          sectionTitle('Productos'),
          table(
            const ['Producto', 'Cant.', 'Precio', 'Subtotal'],
            [
              for (final item in sale.items)
                [
                  item.productName,
                  '${item.quantity}',
                  formatMoney(item.unitPrice),
                  formatMoney(item.subtotal),
                ],
            ],
          ),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                'Total: ${formatMoney(sale.total)}',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: dark,
                ),
              ),
            ),
          ),
          if (sale.isCredit) ...[
            sectionTitle('Resumen de crédito'),
            dataRow('Saldo financiado', formatMoney(sale.financedAmount)),
            dataRow(
              'Interés',
              '${sale.monthlyInterestRate.toStringAsFixed(2)}% mensual · '
                  '${formatMoney(sale.totalInterest)}',
            ),
            dataRow('Total a pagar', formatMoney(sale.totalWithInterest)),
          ],
          sectionTitle('Plan de pagos'),
          table(
            const ['Concepto', 'Vence', 'Monto'],
            [
              for (final payment in sale.payments)
                [
                  '${payment.kindLabel} ${payment.installmentNumber}',
                  formatDate(payment.dueDate),
                  formatMoney(payment.amount),
                ],
            ],
          ),
        ],
      ),
    );
    return document.save();
  }

  static Future<bool> sendEmail(Sale sale) async {
    final subject = 'Plan de pagos ${sale.saleNumber} · CrediStore';
    final uri = Uri(
      scheme: 'mailto',
      path: sale.clientEmail ?? '',
      queryParameters: {'subject': subject, 'body': planText(sale)},
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<bool> sendWhatsApp(Sale sale) async {
    final phone = (sale.clientPhone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.https('wa.me', phone.isEmpty ? '/' : phone, {
      'text': planText(sale),
    });
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
