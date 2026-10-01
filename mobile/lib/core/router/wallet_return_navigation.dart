Map<String, String>? walletReturnParameters(Uri uri) {
  final trusted = uri.host.isEmpty ||
      (uri.scheme == 'https' &&
          {'denkma.com', 'www.denkma.com', 'api.denkma.com'}
              .contains(uri.host)) ||
      (uri.scheme == 'denkma' && uri.host == 'app');
  if (!trusted) return null;
  final path = uri.path.replaceAll(RegExp(r'/+$'), '');
  if (!{
    '/app',
    '/app/parcel',
    '/parcel',
    '/wallet/stripe/success',
    '/wallet/stripe/cancel'
  }.contains(path)) {
    return null;
  }
  final result = uri.queryParameters['wallet_return'] ??
      (path.startsWith('/wallet/stripe/') ? path.split('/').last : null);
  if (result != 'success' && result != 'cancel') return null;
  final topupId = uri.queryParameters['topup_id'];
  return {
    'wallet_return': result!,
    if (topupId != null && RegExp(r'^top_[a-zA-Z0-9]+$').hasMatch(topupId))
      'topup_id': topupId,
  };
}
