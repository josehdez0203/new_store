import 'package:credit_store_app/features/sales/models/sale.dart';
import 'package:credit_store_app/features/sales/services/sale_export.dart';
import 'package:flutter_test/flutter_test.dart';

Sale _sale() {
  return Sale(
    id: 'sale-1',
    saleNumber: 'V-000001',
    clientId: 'client-1',
    clientName: 'María López',
    clientPhone: '5551234567',
    clientEmail: 'maria@example.com',
    sellerId: 'seller-1',
    sellerName: 'Vendedor Demo',
    saleDate: DateTime(2026, 10, 27),
    status: SaleStatuses.sale,
    paymentType: PaymentTypes.credit,
    downPaymentPercent: 20,
    downPayment: 2000,
    financedAmount: 8000,
    monthlyInterestRate: 2,
    months: 6,
    totalInterest: 960,
    total: 10000,
    items: const [
      SaleItem(
        id: 'item-1',
        productId: 'product-1',
        productName: 'Microinversor',
        quantity: 2,
        unitPrice: 5000,
        subtotal: 10000,
      ),
    ],
    payments: const [
      SalePayment(
        id: 'payment-0',
        installmentNumber: 0,
        kind: 'anticipo',
        dueDate: null,
        amount: 2000,
      ),
      SalePayment(
        id: 'payment-1',
        installmentNumber: 1,
        kind: 'mensualidad',
        dueDate: null,
        amount: 1493.33,
      ),
    ],
  );
}

void main() {
  test('el plan de pagos incluye anticipo, interés y mensualidades', () {
    final text = SaleExport.planText(_sale());
    expect(text, contains('V-000001'));
    expect(text, contains('Anticipo'));
    expect(text, contains('Interés'));
    expect(text, contains('Mensualidad 1'));
    expect(text, contains('Total a pagar'));
  });

  test('genera un PDF con el detalle de la venta y su plan', () async {
    final bytes = await SaleExport.buildPdf(_sale());
    expect(bytes.length, greaterThan(1000));
  });
}
