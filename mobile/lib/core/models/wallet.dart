class Wallet {
  const Wallet({
    required this.id,
    required this.userId,
    required this.balance,
    required this.currency,
    this.pendingBalance = 0,
  });

  final String id;
  final String userId;
  final double balance;
  final String currency;
  final double pendingBalance;

  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
        id: json['wallet_id'] as String? ?? json['id'] as String? ?? '',
        userId: json['owner_id'] as String? ?? json['user_id'] as String? ?? '',
        balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
        currency: json['currency'] as String? ?? 'XOF',
        pendingBalance: (json['pending'] as num?)?.toDouble() ??
            (json['pending_balance'] as num?)?.toDouble() ??
            0,
      );
}

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.walletId,
    required this.type,
    required this.amount,
    required this.currency,
    required this.createdAt,
    this.description,
    this.reference,
  });

  final String id;
  final String walletId;

  /// Types : credit | debit | payout | commission
  final String type;
  final double amount;
  final String currency;
  final DateTime createdAt;
  final String? description;
  final String? reference;

  factory WalletTransaction.fromJson(Map<String, dynamic> json) =>
      WalletTransaction(
        id: json['tx_id'] as String? ?? json['id'] as String? ?? '',
        walletId: json['wallet_id'] as String? ?? '',
        type: json['tx_type'] as String? ?? json['type'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
        currency: json['currency'] as String? ?? 'XOF',
        createdAt: DateTime.parse(json['created_at'] as String),
        description: json['description'] as String?,
        reference: json['reference'] as String?,
      );

  bool get isCredit => type == 'credit';
}

class PayoutRequest {
  const PayoutRequest({
    required this.id,
    required this.userId,
    required this.amount,
    required this.method,
    required this.phoneNumber,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final double amount;

  /// Méthodes : wave | orange_money | free_money
  final String method;
  final String phoneNumber;

  /// Statuts : pending | approved | rejected
  final String status;
  final DateTime createdAt;

  factory PayoutRequest.fromJson(Map<String, dynamic> json) => PayoutRequest(
        id: json['payout_id'] as String? ?? json['id'] as String? ?? '',
        userId: json['owner_id'] as String? ?? json['user_id'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
        method: json['method'] as String? ?? '',
        phoneNumber:
            json['phone'] as String? ?? json['phone_number'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}
