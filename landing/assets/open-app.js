(() => {
  const params = new URLSearchParams(window.location.search);
  const phone = params.get('phone') || '';
  const tracking = params.get('tracking') || params.get('tracking_code') || '';
  const referral = (params.get('ref') || params.get('code') || '').trim().toUpperCase();
  const result = params.get('wallet_return');
  const wallet = result === 'success' || result === 'cancel';
  const deeplink = new URL(!wallet && referral
    ? `denkma://app/referral/${encodeURIComponent(referral)}`
    : 'denkma://app/parcel');

  if (wallet) {
    deeplink.searchParams.set('wallet_return', result);
    const topupId = params.get('topup_id') || '';
    if (/^top_[a-zA-Z0-9]+$/.test(topupId)) deeplink.searchParams.set('topup_id', topupId);
    document.getElementById('title').textContent = 'Retour à votre solde';
    document.getElementById('intro').textContent = 'Ouvrez Denkma pour vérifier votre recharge et actualiser votre solde.';
    document.getElementById('context').textContent = result === 'success'
      ? 'Le paiement sera vérifié directement auprès de Stripe. Ne payez pas une deuxième fois.'
      : 'Vous avez quitté le paiement. Consultez son état dans Denkma avant de recommencer.';
    document.getElementById('openApp').textContent = 'Retourner dans Denkma';
    document.getElementById('fallback').textContent = 'Si l’application ne s’ouvre pas automatiquement, appuyez sur le bouton. Vous pouvez aussi ouvrir Denkma, aller dans Solde et actualiser.';
  } else {
    if (phone) deeplink.searchParams.set('phone', phone);
    if (tracking) deeplink.searchParams.set('tracking', tracking);
    if (referral) {
      document.getElementById('title').textContent = 'Utilisez votre code de parrainage';
      document.getElementById('intro').textContent = 'Ouvrez Denkma pour créer votre compte avec le code reçu. Si l’application n’est pas encore installée, téléchargez-la puis revenez sur ce lien.';
      document.getElementById('context').textContent = `Code parrainage ${referral} détecté.`;
    } else {
      document.getElementById('context').textContent = tracking
        ? `Suivi ${tracking} détecté.`
        : 'Votre numéro permettra de retrouver vos colis reçus.';
    }
  }
  document.getElementById('openApp').href = deeplink.toString();
  window.setTimeout(() => { window.location.href = deeplink.toString(); }, 900);
})();
