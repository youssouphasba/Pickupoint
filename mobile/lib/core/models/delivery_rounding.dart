class DeliveryRounding {
  const DeliveryRounding({
    this.customerDiscount = 0,
    this.driverBonus = 0,
    this.denkmaContribution = 0,
  });

  final double customerDiscount;
  final double driverBonus;
  final double denkmaContribution;

  factory DeliveryRounding.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> asMap(Object? value) =>
        value is Map ? Map<String, dynamic>.from(value) : const {};
    double amount(Object? value) {
      final result = value is num ? value.toDouble() : 0.0;
      return result.isFinite && result > 0 ? result : 0.0;
    }

    final contract = asMap(asMap(json['financial_contract'])['breakdown']);
    final snapshot = contract.isNotEmpty
        ? contract
        : asMap(json['financial_rounding']).isNotEmpty
            ? asMap(json['financial_rounding'])
            : asMap(asMap(json['quote_breakdown'] ?? json['breakdown'])[
                'financial_rounding']);
    final rounding = asMap(snapshot['rounding']);
    if (rounding['version'] == null) return const DeliveryRounding();
    return DeliveryRounding(
      customerDiscount: amount(rounding['customer_discount_xof']),
      driverBonus: amount(rounding['driver_bonus_xof']),
      denkmaContribution: amount(rounding['denkma_contribution_xof']),
    );
  }
}
