class CreateParcelPrefill {
  const CreateParcelPrefill({
    this.source,
    this.externalRef,
    this.recipientName,
    this.recipientPhone,
    this.deliveryAddressLabel,
    this.deliveryAddressDistrict,
    this.deliveryAddressCity,
    this.declaredValue,
    this.description,
  });

  final String? source;
  final String? externalRef;
  final String? recipientName;
  final String? recipientPhone;
  final String? deliveryAddressLabel;
  final String? deliveryAddressDistrict;
  final String? deliveryAddressCity;
  final double? declaredValue;
  final String? description;

  bool get hasData =>
      (source ?? '').trim().isNotEmpty ||
      (externalRef ?? '').trim().isNotEmpty ||
      (recipientName ?? '').trim().isNotEmpty ||
      (recipientPhone ?? '').trim().isNotEmpty ||
      (deliveryAddressLabel ?? '').trim().isNotEmpty ||
      (deliveryAddressDistrict ?? '').trim().isNotEmpty ||
      (deliveryAddressCity ?? '').trim().isNotEmpty ||
      declaredValue != null ||
      (description ?? '').trim().isNotEmpty;
}
