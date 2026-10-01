(() => {
  const destination = new URL('/app/', window.location.origin);
  const result = window.location.pathname.includes('/cancel') ? 'cancel' : 'success';
  const topupId = new URLSearchParams(window.location.search).get('topup_id') || '';
  destination.searchParams.set('wallet_return', result);
  if (/^top_[a-zA-Z0-9]+$/.test(topupId)) destination.searchParams.set('topup_id', topupId);
  document.getElementById('continue').href = destination.toString();
  window.location.replace(destination.toString());
})();
