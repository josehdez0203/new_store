/// Estados de una venta.
abstract final class SaleStatuses {
  static const String quote = 'cotizacion';
  static const String sale = 'venta';
  static const String canceled = 'cancelada';

  static const List<String> createValues = [quote, sale];
  static const List<String> values = [quote, sale, canceled];

  static String label(String status) {
    return switch (status) {
      quote => 'Cotización',
      sale => 'Venta',
      canceled => 'Cancelada',
      _ => status,
    };
  }
}

/// Formas de pago.
abstract final class PaymentTypes {
  static const String cash = 'contado';
  static const String credit = 'credito';

  static String label(String type) {
    return switch (type) {
      cash => 'Contado',
      credit => 'Crédito',
      _ => type,
    };
  }
}

/// Configuración persistente de financiamiento de la empresa.
class CreditSettings {
  const CreditSettings({
    required this.downPaymentOptions,
    required this.creditMonths,
    required this.monthlyInterestRate,
    this.updatedAt,
  });

  final List<double> downPaymentOptions;
  final List<int> creditMonths;
  final double monthlyInterestRate;
  final DateTime? updatedAt;

  factory CreditSettings.fromJson(Map<String, dynamic> json) {
    return CreditSettings(
      downPaymentOptions: _doubleList(json['down_payment_options']),
      creditMonths: _intList(json['credit_months']),
      monthlyInterestRate:
          (json['monthly_interest_rate'] as num?)?.toDouble() ?? 0,
      updatedAt: _date(json['updated_at']),
    );
  }

  static List<double> _doubleList(dynamic value) {
    if (value is List) {
      return value.whereType<num>().map((item) => item.toDouble()).toList();
    }
    return const [];
  }

  static List<int> _intList(dynamic value) {
    if (value is List) {
      return value.whereType<num>().map((item) => item.toInt()).toList();
    }
    return const [];
  }

  static DateTime? _date(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

class SaleItem {
  const SaleItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });

  final String id;
  final String productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double subtotal;

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    return SaleItem(
      id: json['id'] as String? ?? '',
      productId: json['product_id'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
    );
  }
}

class SalePayment {
  const SalePayment({
    required this.id,
    required this.installmentNumber,
    required this.kind,
    required this.dueDate,
    required this.amount,
  });

  final String id;
  final int installmentNumber;
  final String kind;
  final DateTime? dueDate;
  final double amount;

  String get kindLabel {
    return switch (kind) {
      'anticipo' => 'Anticipo',
      'mensualidad' => 'Mensualidad',
      'contado' => 'Contado',
      _ => kind,
    };
  }

  factory SalePayment.fromJson(Map<String, dynamic> json) {
    return SalePayment(
      id: json['id'] as String? ?? '',
      installmentNumber: (json['installment_number'] as num?)?.toInt() ?? 0,
      kind: json['kind'] as String? ?? '',
      dueDate: _date(json['due_date']),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
    );
  }

  static DateTime? _date(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

/// Venta o cotización.
class Sale {
  const Sale({
    required this.id,
    required this.saleNumber,
    required this.clientId,
    required this.clientName,
    required this.sellerId,
    required this.sellerName,
    required this.saleDate,
    required this.status,
    required this.paymentType,
    required this.downPaymentPercent,
    required this.downPayment,
    required this.financedAmount,
    required this.monthlyInterestRate,
    required this.months,
    required this.totalInterest,
    required this.total,
    required this.items,
    required this.payments,
    this.clientPhone,
    this.clientEmail,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String saleNumber;
  final String clientId;
  final String clientName;
  final String? clientPhone;
  final String? clientEmail;
  final String sellerId;
  final String sellerName;
  final DateTime? saleDate;
  final String status;
  final String paymentType;
  final double downPaymentPercent;
  final double downPayment;
  final double financedAmount;
  final double monthlyInterestRate;
  final int months;
  final double totalInterest;
  final double total;
  final List<SaleItem> items;
  final List<SalePayment> payments;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isCredit => paymentType == PaymentTypes.credit;
  bool get isCanceled => status == SaleStatuses.canceled;
  bool get isQuote => status == SaleStatuses.quote;
  double get totalWithInterest => total + totalInterest;

  factory Sale.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final rawPayments = json['payments'];
    return Sale(
      id: json['id'] as String? ?? '',
      saleNumber: json['sale_number'] as String? ?? '',
      clientId: json['client_id'] as String? ?? '',
      clientName: json['client_name'] as String? ?? '',
      clientPhone: _nullableString(json['client_phone']),
      clientEmail: _nullableString(json['client_email']),
      sellerId: json['seller_id'] as String? ?? '',
      sellerName: json['seller_name'] as String? ?? '',
      saleDate: _date(json['sale_date']),
      status: json['status'] as String? ?? SaleStatuses.quote,
      paymentType: json['payment_type'] as String? ?? PaymentTypes.cash,
      downPaymentPercent:
          (json['down_payment_percent'] as num?)?.toDouble() ?? 0,
      downPayment: (json['down_payment'] as num?)?.toDouble() ?? 0,
      financedAmount: (json['financed_amount'] as num?)?.toDouble() ?? 0,
      monthlyInterestRate:
          (json['monthly_interest_rate'] as num?)?.toDouble() ?? 0,
      months: (json['months'] as num?)?.toInt() ?? 0,
      totalInterest: (json['total_interest'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      items: rawItems is List
          ? rawItems
                .whereType<Map<String, dynamic>>()
                .map(SaleItem.fromJson)
                .toList(growable: false)
          : const [],
      payments: rawPayments is List
          ? rawPayments
                .whereType<Map<String, dynamic>>()
                .map(SalePayment.fromJson)
                .toList(growable: false)
          : const [],
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
    );
  }

  static String? _nullableString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    return null;
  }

  static DateTime? _date(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
