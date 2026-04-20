POLITIQUE DE CONFIDENTIALITÉ — DENKMA

Dernière mise à jour : [À COMPLÉTER: date de mise en ligne]
Version : 1.0

1. PRÉAMBULE

La présente Politique de Confidentialité décrit comment Denkma (« nous ») collecte, utilise, conserve et protège vos données personnelles lorsque vous utilisez notre plateforme (site denkma.com, application mobile, API). Elle est conforme à la Loi sénégalaise n° 2008-12 du 25 janvier 2008 sur la protection des données à caractère personnel, sous contrôle de la Commission des Données Personnelles (CDP) du Sénégal.

2. RESPONSABLE DU TRAITEMENT

[À COMPLÉTER: raison sociale], immatriculée au RCCM sous le numéro [À COMPLÉTER: RCCM], dont le siège est situé [À COMPLÉTER: adresse], Sénégal.
Contact : privacy@denkma.com
Déclaration CDP : [À COMPLÉTER: numéro de récépissé CDP lorsque disponible]

3. DONNÉES COLLECTÉES

Selon votre rôle (client, livreur, point relais, administrateur), nous collectons :

3.1. Données d'identification
- Nom, prénom, téléphone, email (admin), date de naissance, photo de profil.
- Pour livreurs et points relais : pièce d'identité, permis de conduire, carte grise, justificatif de local, numéro d'agrément le cas échéant (données KYC).

3.2. Données de compte
- Code PIN (haché), jetons d'authentification (JWT), historique de connexion.

3.3. Données de livraison
- Adresse de collecte et de livraison (texte + GPS), poids et description du colis, destinataire, notes vocales, photos à la livraison.

3.4. Données de géolocalisation
- Position en temps réel du livreur pendant les missions actives.
- Position GPS de l'expéditeur au moment de la création et de la confirmation du colis.

3.5. Données financières
- Historique des paiements et des virements (reçus et envoyés).
- Coordonnées de paiement fournies à notre prestataire Flutterwave (Wave, Orange Money, Free Money). Denkma ne stocke pas les numéros de compte bancaire complets.
- Demandes de retrait (payouts) avec numéro mobile money ou compte bancaire destinataire.

3.6. Données techniques
- Adresse IP, modèle d'appareil, système d'exploitation, identifiants de notification (Firebase FCM), données d'usage de l'application.

3.7. Données de support
- Messages échangés avec le service client, signalements, litiges.

4. FINALITÉS DU TRAITEMENT

Nous utilisons vos données pour :
- créer et gérer votre compte ;
- authentifier vos connexions (OTP par SMS/WhatsApp) ;
- exécuter les missions de livraison et mettre en relation expéditeurs, livreurs, points relais, destinataires ;
- calculer les tarifs, commissions et versements ;
- traiter les paiements via Flutterwave ;
- assurer le suivi GPS et envoyer des notifications push ;
- prévenir la fraude et sécuriser la plateforme ;
- améliorer nos services (analytics internes, modèles ML de pricing dynamique) ;
- respecter nos obligations légales et fiscales ;
- communiquer des informations de service, et, avec votre consentement explicite, des offres promotionnelles.

5. BASES LÉGALES

- Exécution du contrat : création de compte, livraisons, paiements, support.
- Obligation légale : conservation fiscale et comptable, KYC livreur/relais, réponse aux autorités.
- Intérêt légitime : prévention de la fraude, sécurité, amélioration des services.
- Consentement : notifications marketing, collecte de géolocalisation en arrière-plan, envois WhatsApp non transactionnels.

6. DESTINATAIRES DES DONNÉES

Vos données sont partagées uniquement avec :
- Les autres utilisateurs nécessaires à la livraison (livreur, point relais, destinataire) — téléphones masqués lorsque non indispensables.
- Nos sous-traitants techniques :
  • Railway (hébergement backend) — [À COMPLÉTER: localisation serveur, ex. USA/Europe]
  • MongoDB Atlas (base de données) — [À COMPLÉTER: région, ex. Frankfurt]
  • Cloudflare (CDN, hébergement dashboard)
  • Firebase / Google (authentification, notifications push, Maps)
  • Flutterwave (paiements)
  • Firebase Authentication (Google) — envoi de l'OTP SMS à l'inscription
  • Meta/WhatsApp Business API — notifications de suivi colis
  • Amazon S3 ou stockage local (photos profil, KYC, notes vocales) — [À COMPLÉTER: préciser fournisseur et région]
- Les autorités compétentes, uniquement sur demande légale valide.

Nous ne vendons jamais vos données à des tiers.

7. TRANSFERTS HORS DU SÉNÉGAL

Certains prestataires (Railway, MongoDB Atlas, Firebase, Cloudflare) hébergent des données hors du Sénégal. Ces transferts sont encadrés par les engagements contractuels de ces prestataires et, le cas échéant, par des clauses-types de protection reconnues internationalement (équivalent CCT). Vous pouvez obtenir une copie de ces garanties sur simple demande.

8. DURÉES DE CONSERVATION

- Compte actif : tant que le compte est ouvert.
- Données de livraison : 5 ans après la dernière livraison (obligation comptable).
- Données KYC (livreur/relais) : 5 ans après résiliation.
- Historique de géolocalisation par mission : [À COMPLÉTER: durée, ex. 90 jours] après clôture.
- Journaux techniques : 12 mois.
- Compte supprimé : anonymisation sous 30 jours, sauf obligations légales contraires.

9. VOS DROITS

Conformément à la Loi 2008-12, vous disposez des droits suivants :
- droit d'accès à vos données ;
- droit de rectification des données inexactes ;
- droit d'effacement (« droit à l'oubli ») ;
- droit d'opposition au traitement ;
- droit à la portabilité ;
- droit de limitation du traitement ;
- droit de retirer votre consentement à tout moment ;
- droit d'introduire une réclamation auprès de la CDP Sénégal (www.cdp.sn).

Pour exercer ces droits, contactez-nous à privacy@denkma.com en joignant une copie d'un justificatif d'identité. Nous répondrons sous 30 jours.

10. SÉCURITÉ

Nous mettons en œuvre des mesures techniques et organisationnelles :
- chiffrement TLS 1.2+ pour tous les échanges ;
- hashage des codes PIN (bcrypt) et des jetons ;
- authentification par JWT signés ;
- contrôles d'accès par rôle côté API ;
- audit logs de toutes les opérations sensibles ;
- sauvegardes régulières de la base de données.

Aucun système n'étant infaillible, nous vous invitons à protéger votre code PIN et votre téléphone.

11. COOKIES ET TRACEURS

11.1. Application mobile : nous utilisons des identifiants techniques (token FCM, token d'authentification) strictement nécessaires au fonctionnement.

11.2. Site web (denkma.com, admin.denkma.com) : nous utilisons des cookies :
- strictement nécessaires (session d'authentification admin) ;
- [À COMPLÉTER: de mesure d'audience, ex. Plausible Analytics, si activé] ;
Aucun cookie publicitaire tiers.

12. MINEURS

Denkma n'est pas destinée aux personnes de moins de 18 ans. Nous ne collectons pas sciemment de données de mineurs. Si vous constatez qu'un mineur nous a transmis des données, contactez-nous pour suppression immédiate.

13. VOIX, IMAGES, GÉOLOCALISATION

- Les notes vocales (pickup_voice_note, delivery_voice_note) sont associées au colis concerné et accessibles aux parties à la livraison.
- Les photos de profil sont visibles des autres parties à la livraison.
- Les documents KYC ne sont accessibles qu'aux administrateurs de Denkma pour validation de compte.
- La géolocalisation en arrière-plan du livreur n'est active que pendant les missions acceptées.

14. MODIFICATIONS

Nous pouvons modifier cette politique pour refléter les évolutions légales ou fonctionnelles. Toute modification substantielle sera notifiée dans l'application et par email (admins). La date de mise à jour figure en haut de la politique.

15. CONTACT

Pour toute question relative à vos données :
Email : privacy@denkma.com
Courrier : Denkma — Délégué à la Protection des Données
[À COMPLÉTER: adresse siège], Sénégal

Autorité de contrôle : Commission des Données Personnelles du Sénégal (CDP) — www.cdp.sn
