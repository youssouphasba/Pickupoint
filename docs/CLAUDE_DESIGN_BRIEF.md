# Brief Claude Design — Denkma

**Comment l'utiliser** : copie-colle la section « Prompt à envoyer » ci-dessous dans Claude Design (claude.ai → Claude Design). Attache aussi : `landing/assets/logo.png`, les variantes logo de la racine (`denkma_logo_*.png`), et une capture de `landing/index.html` actuelle.

---

## Prompt à envoyer

> Je veux refondre la landing page de **Denkma**, une plateforme sénégalaise de livraison et de points relais. Objectif : convertir les visiteurs en téléchargements d'app (Android / iOS bientôt disponibles) et en candidatures partenaires (livreurs, commerces relais).
>
> ### Contexte produit
> - **Pays** : Sénégal (Dakar en priorité, FR fr-SN)
> - **Utilisateurs** : clients (expéditeurs / destinataires), livreurs, points relais (commerces partenaires), admins
> - **Différenciateur** : 4 modes de livraison — domicile↔domicile, domicile↔relais, relais↔domicile, relais↔relais
> - **Prix d'appel** : à partir de **700 XOF** (relais↔relais) jusqu'à 1 300 XOF (domicile↔domicile), + km + kg + express
> - **Preuves de confiance** : suivi temps réel, code PIN de retrait, notifications WhatsApp, preuves photo livreur
> - **Paiement** : Wave, Orange Money, Free Money (via Flutterwave) + cash à la livraison
>
> ### Identité visuelle (à appliquer strictement)
> - **Primary** : `#0b8a5f` (vert Denkma) — CTA, icônes, accents forts
> - **Primary dark** : `#076e4b` — hover, gradients
> - **Primary soft** : `#e6f5ef` — backgrounds pilules / icônes
> - **Accent** : `#ffb703` (jaune safran) — badges "nouveau", highlights
> - **Dark** : `#0f1b17` (footer), texte `#1a1a1a`, muted `#555`
> - **Typo** : moderne sans-serif (Inter ou Manrope), titres 700-800 avec letter-spacing légèrement serré
> - **Ton** : chaleureux, concret, fier (Dakar / Sénégal), zéro jargon tech
> - **Iconographie** : Lucide / Feather (stroke 1.75-2, lineCap round)
> - **Ambiance** : moderne africaine — éviter clichés "safari", favoriser Dakar urbain (mobylettes, marchés, tissus wax subtils en motifs, pas en photos)
>
> ### Objectif n°1 — une page **VIVANTE**, pas un catalogue statique
> La version actuelle est correcte mais morte : fond blanc, blocs figés, aucun mouvement, zéro émotion. Je veux une page qui **raconte une histoire en scrollant** et qui donne envie de télécharger l'app dès les 3 premières secondes. Motion design soigné, pas gadget.
>
> ### Sections souhaitées (dans cet ordre)
> 1. **Hero animé**
>    - Titre qui apparaît mot par mot (stagger fade-in)
>    - Illustration SVG animée à droite : un **colis qui voyage** d'une maison vers un point relais vers une autre maison, avec un trait pointillé qui se dessine progressivement (SMIL ou CSS keyframes). Loop toutes les 6-8 s.
>    - En arrière-plan : **gradient doux qui respire** (lent shift vert → vert foncé, cycle 20 s), et motif wax en opacité 5 % qui défile lentement en parallax
>    - 2 CTA : primary (Télécharger) avec **pulse léger** toutes les 3 s ; secondary (Devenir partenaire)
>    - Badge de confiance animé en dessous : compteur qui monte ("0 → 1 247 colis livrés") au chargement
> 2. **Ticker défilant** (après hero) — bande fine avec marquee : "Dakar · Pikine · Guédiawaye · Rufisque · Thiès · Touba · Saint-Louis…" pour montrer la couverture géographique
> 3. **Comment ça marche** (4 étapes) — chaque étape s'anime à l'apparition (scroll-triggered), icônes qui **dessinent leur tracé** (stroke-dasharray animé). Flèches de liaison entre étapes qui se dessinent au scroll.
> 4. **4 modes de livraison** — cards avec flux **maison → relais** animé au hover (icônes qui se déplacent, trait pointillé qui avance). Afficher prix de base : **700 / 900 / 1 100 / 1 300 XOF**. Badge "Le + économique" sur relais↔relais, badge "Le + rapide" sur domicile↔domicile.
> 5. **Carte du Sénégal interactive** — silhouette SVG du pays avec **pins qui apparaissent un par un** (Dakar, Thiès, Saint-Louis, Touba…) avec effet radar ping autour de chaque pin. Compteur "X relais partenaires" qui s'incrémente en face.
> 6. **Pour qui** (3 cards animées) — clients / livreurs / relais. Chaque card bascule en 3D légèrement au hover (transform rotateY 3-5°). CTA différencié par audience.
> 7. **Preuves sociales vivantes**
>    - **3 compteurs animés** au scroll (colis livrés / livreurs actifs / relais partenaires) — effet counter-up
>    - **Témoignages en carrousel auto** (3 avatars placeholders + étoiles, rotation toutes les 5 s avec fade)
> 8. **Fonctionnalités** (grille 6) — icônes avec **micro-animations loop** (ex. cloche qui sonne, œil qui cligne pour suivi, QR qui scanne). Hover = glow vert.
> 9. **FAQ accordion** — ouverture smooth (max-height transition + chevron qui tourne)
> 10. **CTA final + download** — background gradient **animé en conic-gradient** qui tourne lentement derrière. Badges Google Play / App Store (mention "bientôt disponible").
> 11. **Footer** — liens produit, légal (privacy / terms), contact, réseaux sociaux
>
> ### Motion design — règles à respecter
> - **Scroll-triggered** : chaque section fade + translate-y 20px → 0 à l'apparition (Intersection Observer, 600 ms ease-out)
> - **Stagger** : dans une grille, chaque enfant a 80 ms de delay de plus que le précédent
> - **Hover** : transforme + ombre colorée vert (pas de box-shadow gris triste)
> - **Durées** : 200-400 ms pour les hovers, 600-800 ms pour les entrées de section, 3-8 s pour les loops ambiants
> - **Easing** : `cubic-bezier(0.4, 0, 0.2, 1)` par défaut, bounce léger sur les compteurs
> - **`prefers-reduced-motion`** : désactiver tous les loops ambiants et ticker, garder uniquement les fondus simples — **non négociable pour l'accessibilité**
>
> ### Contraintes
> - **Mobile-first** (80 % du trafic sera mobile) — les animations doivent rester **fluides sur Android entrée de gamme** (pas de blur backdrop lourd, pas de shadow multiples)
> - **Performance** : SVG inline + CSS animations (pas de librairie JS lourde type GSAP sauf si vraiment nécessaire). Lottie accepté pour 1-2 éléments hero max.
> - **Accessibilité** : contrastes AA minimum, focus visible sur CTA, `prefers-reduced-motion` respecté
> - **SEO** : structure sémantique (h1 unique, h2 par section), microdata conservé (la version actuelle a schema.org FAQ + Organization + SoftwareApplication — à garder)
> - **i18n** : texte en français (fr-SN), devises en XOF
>
> ### Export attendu
> HTML/CSS inline exportable vers **Claude Code** — je l'intégrerai ensuite dans `landing/index.html` du repo Denkma.

---

## Checklist à préparer avant d'envoyer

- [ ] Logo PNG haute résolution (utiliser `denkma_logo_store_app_1024_centered.png`)
- [ ] Logo transparent (`denkma_logo_proposal_1_clean_transparent.png`)
- [ ] Capture d'écran de la landing actuelle (contre-exemple pour qu'il évite les mêmes faiblesses)
- [ ] 2-3 captures réelles de l'app Flutter (écran création colis, suivi, carte drivers) — permettent à Claude Design de générer un mockup de téléphone crédible
- [ ] Palette exacte (déjà dans le brief)

## Itérations prévues après la v1

1. Ajuster la densité d'info mobile (souvent trop longue en v1)
2. Tester une variante **hero avec vidéo** vs **hero avec mockup**
3. Générer une version **partenaire commerce relais** dédiée (sous-page `/relais`)
4. Générer une version **recrutement livreurs** dédiée (sous-page `/livreurs`)
5. Exporter en HTML → je l'intègre dans `landing/` via Claude Code et j'ajoute les liens légaux `/privacy` et `/terms`

---

## Prompts dédiés — 4 scènes animées pour les modes de livraison

> **Contexte technique** : Claude Design génère du HTML/CSS/SVG exportable. Pour ces scènes, demande-lui **des SVG animés en CSS/SMIL** (loop 8-10 s, sans JS). C'est plus léger qu'une vidéo MP4, éditable après coup, et ça tourne partout (Android entrée de gamme compris). Si tu veux du format vidéo MP4 pour les réseaux sociaux, enregistre ensuite l'écran en lecture.

### Consignes visuelles communes à toutes les scènes

> Style **flat illustration moderne africaine**, couleurs Denkma (`#0b8a5f` primary, `#076e4b` dark, `#ffb703` accent jaune, fonds `#f4faf7`). Silhouettes de personnages simples avec touches de **tissu wax subtiles** (1-2 motifs par personnage, pas de cliché). Architecture sénégalaise : maisons à toits plats aux murs colorés (terre, ocre, blanc cassé), boutique-relais avec enseigne **verte avec logo "D"**. Véhicule livreur : **scooter / mobylette** (typique Dakar), casque. Colis : **cube marron/beige avec ruban vert Denkma**. Pas de texte dans la scène (hors enseigne relais). Format **1:1 ou 16:9**, loop fluide de **8-10 secondes**, retour invisible au début. Respecter `prefers-reduced-motion` (version statique avec poses clés).

### Scène 1 — Domicile → Domicile (1 300 XOF)

> Génère une **scène SVG animée en loop (10 s)** illustrant le mode **Domicile → Domicile** de Denkma.
>
> **Narration visuelle** :
> - **0-2 s** : à gauche, l'**expéditrice** (femme en boubou coloré) sort de sa maison à toit plat, colis dans les mains. Porte qui s'ouvre, léger bounce.
> - **2-4 s** : un **livreur à scooter vert Denkma** arrive par la droite, freine devant la maison. Petit nuage de poussière. Expéditrice lui tend le colis avec un sourire. Scooter a un compartiment arrière (box) marqué d'un "D".
> - **4-6 s** : livreur range le colis dans le box, repart vers la droite. **Trait pointillé vert** qui se dessine derrière lui (trajet).
> - **6-8 s** : arrivée devant la maison du **destinataire** (homme en tenue moderne). Livreur sort le colis, le remet en main propre. Check de téléphone (bulle "✓ livré").
> - **8-10 s** : destinataire rentre chez lui, colis dans les mains. Porte se referme. Fondu vers scène de départ.
>
> Couleurs Denkma, tissu wax subtil sur le boubou de l'expéditrice, ambiance Dakar chaleureuse. Ciel dégradé vert très pâle vers blanc. Format 16:9, SVG + CSS animations (pas de JS), loop infini. Accessibilité : si `prefers-reduced-motion`, afficher seulement 3 poses clés en side-by-side.

### Scène 2 — Domicile → Relais (900 XOF)

> Génère une **scène SVG animée en loop (10 s)** illustrant le mode **Domicile → Relais** de Denkma. **La caméra reste toujours dehors** — on ne voit jamais l'intérieur de la boutique-relais.
>
> **Narration visuelle** :
> - **0-2 s** : expéditeur (homme) sort de sa maison à gauche, colis en main. Livreur à scooter Denkma arrive.
> - **2-4 s** : remise du colis à la porte. Scooter repart vers la droite, trait pointillé vert derrière lui.
> - **4-6 s** : scooter arrive devant une **boutique-relais** (devanture type épicerie sénégalaise, enseigne verte "D", porte fermée). Livreur descend, entre (disparaît brièvement dans la porte, 1 s), ressort sans le colis. Petit ✓ vert qui pop au-dessus de la porte.
> - **6-8 s** : ellipse temporelle (soleil qui glisse dans le ciel). **Destinataire** (femme en tenue colorée) arrive à pied devant la boutique, téléphone en main avec QR vert.
> - **8-10 s** : elle entre dans la boutique (disparaît 1 s), ressort avec le colis sous le bras, sourire. Fondu retour.
>
> Même charte visuelle que scène 1. Toute l'action reste **devant la devanture**. Format 16:9, SVG + CSS animations.

### Scène 3 — Relais → Domicile (1 100 XOF)

> Génère une **scène SVG animée en loop (10 s)** illustrant le mode **Relais → Domicile** de Denkma. **La caméra reste toujours dehors** — on ne voit jamais l'intérieur de la boutique-relais.
>
> **Narration visuelle** :
> - **0-2 s** : expéditrice (femme) marche vers la **boutique-relais** (enseigne verte "D"), colis dans les bras. Entre dans la porte (disparaît 1 s).
> - **2-4 s** : elle ressort **les mains vides**, un petit ✓ vert pop au-dessus de la porte. Elle repart.
> - **4-6 s** : **livreur à scooter** arrive, entre dans la boutique (disparaît 1 s), ressort avec le colis, le range dans son box scooter.
> - **6-8 s** : scooter traverse l'écran vers la droite, trait pointillé vert qui se dessine.
> - **8-10 s** : livreur arrive devant la **maison du destinataire** (homme moderne, téléphone en main). Remise du colis en main propre, notification "✓ livré" qui pop au-dessus du téléphone. Fondu retour.
>
> Même charte. Bien différencier : le **point de départ est le relais**, pas la maison. Action relais **devant la devanture uniquement**. Format 16:9.

### Scène 4 — Relais → Relais (700 XOF — Le + économique)

> Génère une **scène SVG animée en loop (10 s)** illustrant le mode **Relais → Relais** de Denkma. **Badge "Le + économique" en haut à droite**, style pilule verte avec brillance qui passe. **La caméra reste toujours dehors** sur les deux relais.
>
> **Narration visuelle** :
> - **0-2 s** : expéditeur arrive devant une **première boutique-relais** (à gauche, enseigne verte "D"), colis en main. Entre par la porte (disparaît 1 s), ressort **les mains vides**, ✓ vert au-dessus de la porte.
> - **2-4 s** : **livreur à scooter** arrive, entre dans le relais A (disparaît 1 s), ressort avec le colis, le range dans le box scooter.
> - **4-6 s** : scooter traverse l'écran avec **trait pointillé vert qui se dessine sur toute la largeur**. En fond, silhouette stylisée de Dakar (minaret, building, baobab simplifié).
> - **6-8 s** : arrivée devant une **deuxième boutique-relais** (à droite). Livreur entre (disparaît 1 s), ressort les mains vides, ✓ vert au-dessus de la porte.
> - **8-10 s** : destinataire arrive à pied, téléphone avec QR vert en main. Entre dans le relais B (disparaît 1 s), ressort avec le colis, sourire. Fondu retour.
>
> Même charte. Le **trait pointillé long** entre les deux relais met en valeur l'aspect économique. Format 16:9.

### Comment Claude Design va répondre à ces prompts

1. Il générera un **SVG inline** par scène avec des `<animate>` SMIL ou CSS `@keyframes`
2. Tu pourras **itérer** : *« change le sourire de l'agente »*, *« rends le scooter plus gros »*, *« ajoute un baobab en fond »*
3. **Export** : HTML+SVG direct → je l'intègre dans les 4 cards `.mode-card` de `landing/index.html`
4. Alternative si tu veux du MP4 pour **Instagram / TikTok** : une fois la scène SVG validée, enregistre l'écran en lecture (OBS, QuickTime) → convertit en MP4 vertical 9:16 pour les stories

### Astuce : les 4 scènes peuvent aussi devenir un carrousel hero

Si tu préfères, au lieu d'une illustration statique dans le hero, propose à Claude Design de **cycler les 4 scènes** (une toutes les 8 s) avec des dots en bas. Tu gagnes un hero spectaculaire et tu expliques les 4 modes sans que l'utilisateur ait besoin de scroller.

---

## Sous-produits à lancer ensuite dans Claude Design

- **Pitch deck investisseurs** (source : `docs/BUSINESS_PLAN_DENKMA_2026.md`) — format PPTX, 12-15 slides
- **One-pager recrutement livreurs** (PDF A4, imprimable, à distribuer dans les stations Wave)
- **One-pager recrutement relais** (PDF A4, pour démarcher les boutiques)
- **Mockups écrans app** (à valider avant développement Flutter des nouvelles features promotions / récompenses — cf. `PLAN_RECOMPENSES_PROMOTIONS.md`)
