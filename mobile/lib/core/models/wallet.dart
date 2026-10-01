class Wallet {
  const Wallet({
    required this.id,
    required this.userId,
    required this.balance,
    required this.currency,
    this.pendingBalance = 0,
    this.payoutAvailable = true,
    this.payoutBlockReason,
    this.topupOptions,
    this.topups = const [],
  });

  final String id;
  final String userId;
  final double balance;
  final String currency;
  final double pendingBalance;
  final bool payoutAvailable;
  final String? payoutBlockReason;
  final WalletTopupOptions? topupOptions;
  final List<WalletTopup> topups;

  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
        id: json['wallet_id'] as String? ?? json['id'] as String? ?? '',
        userId: json['owner_id'] as String? ?? json['user_id'] as String? ?? '',
        balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
        currency: json['currency'] as String? ?? 'XOF',
        pendingBalance: (json['pending'] as num?)?.toDouble() ??
            (json['pending_balance'] as num?)?.toDouble() ??
            0,
        payoutAvailable: json['payout_available'] as bool? ?? true,
        payoutBlockReason: json['payout_block_reason'] as String?,
        topupOptions: json['topup_options'] is Map<String, dynamic>
            ? WalletTopupOptions.fromJson(
                json['topup_options'] as Map<String, dynamic>)
            : null,
        topups: (json['topups'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(WalletTopup.fromJson)
            .toList(),
      );
}

class WalletTopupOptions {
  const WalletTopupOptions(
      {required this.enabled,
      required this.minimumAmount,
      required this.maximumAmount,
      this.verificationRetrySeconds = 0,
      this.verificationRetryAttempts = 0});

  final bool enabled;
  final double minimumAmount;
  final double maximumAmount;
  final int verificationRetrySeconds;
  final int verificationRetryAttempts;

  factory WalletTopupOptions.fromJson(Map<String, dynamic> json) =>
      WalletTopupOptions(
        enabled: json['enabled'] == true,
        minimumAmount: (json['minimum_amount'] as num).toDouble(),
        maximumAmount: (json['maximum_amount'] as num).toDouble(),
        verificationRetrySeconds:
            (json['verification_retry_seconds'] as num?)?.toInt() ?? 0,
        verificationRetryAttempts:
            (json['verification_retry_attempts'] as num?)?.toInt() ?? 0,
      );
}

class WalletTopup {
  const WalletTopup(
      {required this.id,
      required this.amount,
      required this.status,
      required this.createdAt,
      this.verificationMessage});

  final String id;
  final double amount;
  final String status;
  final DateTime createdAt;
  final String? verificationMessage;

  factory WalletTopup.fromJson(Map<String, dynamic> json) => WalletTopup(
        id: json['topup_id'] as String,
        amount: (json['amount'] as num).toDouble(),
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        verificationMessage: json['verification_message'] as String?,
      );

  bool get isPaid => status == 'paid';
  bool get isPending => status == 'pending';
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

  /// Types : credit | debit | pending | revenue
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

  bool get isCredit => type == 'credit' || type == 'revenue';
  bool get isRevenue => type == 'revenue';
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
    this.updatedAt,
    this.rejectionReason,
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
  final DateTime? updatedAt;
  final String? rejectionReason;

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
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
        rejectionReason: json['rejection_reason'] as String?,
      );
}

class WalletActivity {
  WalletActivity.fromJson(Map<String, dynamic> json)
      : items = (json['items'] as List? ?? [])
            .map((row) => WalletActivityItem.fromJson(
                Map<String, dynamic>.from(row as Map)))
            .toList(),
        total = (json['total'] as num).toInt(),
        earnings = ((json['earnings'] as Map)['amount'] as num).toDouble(),
        coursesCount =
            ((json['earnings'] as Map)['courses_count'] as num).toInt(),
        pendingPayouts = (json['pending_payouts'] as List? ?? [])
            .map((row) =>
                PayoutRequest.fromJson(Map<String, dynamic>.from(row as Map)))
            .toList(),
        pendingTopups = (json['pending_topups'] as List? ?? [])
            .map((row) =>
                WalletTopup.fromJson(Map<String, dynamic>.from(row as Map)))
            .toList();

  final List<WalletActivityItem> items;
  final int total;
  final double earnings;
  final int coursesCount;
  final List<PayoutRequest> pendingPayouts;
  final List<WalletTopup> pendingTopups;
}

class WalletActivityItem {
  WalletActivityItem.fromJson(Map<String, dynamic> json)
      : id = json['tx_id'] as String,
        kind = json['kind'] as String,
        amount = (json['amount'] as num).toDouble(),
        effect = (json['effect'] as num).toDouble(),
        status = json['status'] as String,
        description = json['description'] as String? ?? 'Opération du solde',
        createdAt = DateTime.parse(json['created_at'] as String),
        missionId = json['mission_id'] as String?,
        rejectionReason = json['rejection_reason'] as String?;

  final String id;
  final String kind;
  final double amount;
  final double effect;
  final String status;
  final String description;
  final DateTime createdAt;
  final String? missionId;
  final String? rejectionReason;
}
