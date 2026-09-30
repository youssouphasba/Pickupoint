import {
  AlertTriangle, Banknote, BarChart3, Bell, BellRing, Clock, FileText,
  History, LayoutDashboard, Map, MessageCircle, Package, Scale,
  Settings, Store, Tag, Truck, Trophy, UserRoundCog, Users,
  Wallet, type LucideIcon,
} from "lucide-react";

export type NavigationBadge = "payouts" | "applications" | "anomalies" |
  "stale_parcels" | "support" | "security" | "incidents_payment";

export type AdminLink = { href: string; label: string };
export type AdminSection = { id: string; label: string };
export type AdminPage = {
  href: string;
  label: string;
  description: string;
  Icon: LucideIcon;
  keywords?: string;
  badge?: NavigationBadge;
  steps: string[];
  related: AdminLink[];
  sections?: AdminSection[];
  detailLabel?: string;
};
export type AdminNavigationGroup = { id: string; label: string; pages: AdminPage[] };

export const ADMIN_HOME: AdminPage = {
  href: "/dashboard", label: "Tableau de bord", Icon: LayoutDashboard,
  description: "Les priorités du jour et les principaux indicateurs de l’activité.",
  keywords: "dashboard accueil actions urgences",
  steps: ["Commencez par les éléments à traiter et les urgences.", "Ouvrez un indicateur pour consulter les dossiers concernés.", "Utilisez les accès rapides pour poursuivre dans le bon écran."],
  related: [{ href: "/dashboard/analytics", label: "Analyser une période" }, { href: "/dashboard/settings/alerts", label: "Régler mes alertes" }],
};

export const ADMIN_NAVIGATION: AdminNavigationGroup[] = [
  { id: "operations", label: "Exploitation", pages: [
    {
      href: "/dashboard/parcels", label: "Colis", Icon: Package, badge: "incidents_payment", detailLabel: "Détail du colis",
      description: "Retrouvez un colis, son parcours, son paiement et les actions à mener.", keywords: "livraison mission suivi expéditeur destinataire",
      steps: ["Recherchez par code de suivi et filtrez par statut ou période.", "Ouvrez le code du colis pour accéder aux personnes, au parcours et aux règlements.", "Vérifiez le motif avant toute suspension, réaffectation ou correction de paiement."],
      related: [{ href: "/dashboard/fleet", label: "Suivre les livreurs" }, { href: "/dashboard/finance#paiements-colis", label: "Contrôler les paiements" }],
    },
    {
      href: "/dashboard/fleet", label: "Suivi des livreurs", Icon: Map,
      description: "Localisez les livreurs et vérifiez la fraîcheur de leur dernière position.", keywords: "flotte live gps carte position arrière plan",
      steps: ["Filtrez les livreurs selon leur activité et l’état du signal.", "Sélectionnez un marqueur pour ouvrir les informations du livreur et de sa mission.", "Consultez l’heure du dernier signal : une ancienne position ne garantit pas une présence actuelle."],
      related: [{ href: "/dashboard/drivers", label: "Gérer les livreurs" }, { href: "/dashboard/anomalies", label: "Contrôler les anomalies" }],
    },
    {
      href: "/dashboard/stale", label: "Colis en attente prolongée", Icon: Clock, badge: "stale_parcels",
      description: "Repérez les colis immobilisés en relais et organisez leur relance.", keywords: "stagnants retard retrait relais",
      steps: ["Vérifiez l’ancienneté et le relais qui détient le colis.", "Ouvrez le colis pour examiner son historique et les coordonnées utiles.", "Contactez la personne concernée avant de décider de la suite du parcours."],
      related: [{ href: "/dashboard/parcels", label: "Tous les colis" }, { href: "/dashboard/support", label: "Ouvrir le support" }],
    },
    {
      href: "/dashboard/support", label: "Support WhatsApp", Icon: MessageCircle, badge: "support",
      description: "Répondez aux conversations et suivez celles qui attendent une action.", keywords: "messages vocal client assistance",
      steps: ["Choisissez une conversation et vérifiez le contact et le colis détecté.", "Envoyez votre réponse ; les notes internes ne sont jamais envoyées au contact.", "Classez la conversation selon la suite attendue ou marquez-la résolue."],
      related: [{ href: "/dashboard/parcels", label: "Retrouver un colis" }, { href: "/dashboard/users", label: "Retrouver un compte" }],
    },
  ] },
  { id: "network", label: "Comptes et partenaires", pages: [
    {
      href: "/dashboard/users", label: "Utilisateurs", Icon: Users, detailLabel: "Dossier utilisateur",
      description: "Gérez les comptes, les rôles, les vérifications d’identité et les accès.", keywords: "client compte kyc suspension photo parrainage",
      steps: ["Retrouvez le compte par son nom ou son téléphone.", "Ouvrez son dossier pour consulter ses justificatifs et son activité.", "Vérifiez le rôle et le point relais lié avant de modifier les accès."],
      related: [{ href: "/dashboard/applications", label: "Traiter les candidatures" }, { href: "/dashboard/privacy-requests", label: "Demandes de données" }],
    },
    {
      href: "/dashboard/drivers", label: "Livreurs", Icon: Truck,
      description: "Consultez les comptes livreurs, leur disponibilité, leurs missions et leurs gains.", keywords: "chauffeur moto actif disponible",
      steps: ["Distinguez le statut du compte de la disponibilité du livreur.", "Consultez les missions et la dernière position pour comprendre sa situation.", "Ouvrez le dossier utilisateur pour gérer ses accès ou ses justificatifs."],
      related: [{ href: "/dashboard/fleet", label: "Voir sur la carte" }, { href: "/dashboard/performances", label: "Voir les performances" }],
    },
    {
      href: "/dashboard/relays", label: "Points relais", Icon: Store, detailLabel: "Fiche du point relais",
      description: "Gérez les adresses, les horaires, la capacité et les comptes des points relais.", keywords: "boutique ouvert fermé géocoder agent liaison",
      steps: ["Créez ou ouvrez un relais et vérifiez son emplacement sur la carte.", "Renseignez les jours et horaires d’ouverture ; un jour non sélectionné est fermé.", "Vérifiez le compte associé et les informations de contact avant activation."],
      related: [{ href: "/dashboard/users", label: "Gérer le compte associé" }, { href: "/dashboard/configuration#livraison", label: "Règles de livraison" }],
    },
    {
      href: "/dashboard/applications", label: "Candidatures partenaires", Icon: FileText, badge: "applications",
      description: "Vérifiez les dossiers avant d’accepter un livreur ou un point relais.", keywords: "documents identité validation recrutement kyc",
      steps: ["Filtrez sur les candidatures en attente.", "Ouvrez le dossier et contrôlez les documents et la photo.", "Approuvez le dossier ou indiquez un motif de rejet."],
      related: [{ href: "/dashboard/drivers", label: "Livreurs inscrits" }, { href: "/dashboard/relays", label: "Points relais inscrits" }],
    },
  ] },
  { id: "finance", label: "Finances", pages: [
    {
      href: "/dashboard/finance", label: "Synthèse financière", Icon: Banknote,
      description: "Distinguez commissions, recharges, règlements relais et retraits sur la période choisie.", keywords: "finance argent paiement wallet réconciliation solde trésorerie",
      steps: ["Choisissez la période avant de comparer les montants.", "Contrôlez les éléments à traiter et ouvrez les cartes pour voir les dossiers et les motifs.", "Les paiements clients et les règlements manuels se font hors plateforme ; les chiffres ne remplacent pas une preuve de paiement."],
      related: [{ href: "/dashboard/payouts", label: "Traiter les retraits" }, { href: "/dashboard/configuration#commissions", label: "Régler les commissions" }, { href: "/dashboard/promotions#primes", label: "Règlements du parrainage" }],
      sections: [{ id: "synthese", label: "Synthèse" }, { id: "controles", label: "Contrôles" }, { id: "paiements-colis", label: "Paiements colis" }, { id: "commissions", label: "Commissions" }, { id: "recharges", label: "Recharges" }, { id: "relais", label: "Règlements relais" }, { id: "retraits", label: "Retraits" }, { id: "soldes", label: "Soldes" }, { id: "mouvements", label: "Mouvements" }],
    },
    {
      href: "/dashboard/payouts", label: "Demandes de retrait", Icon: Wallet, badge: "payouts",
      description: "Traitez les retraits demandés et conservez la référence de chaque versement.", keywords: "décaissement paiement transfert wave",
      steps: ["Vérifiez le bénéficiaire, le montant et la destination du versement.", "Effectuez le paiement hors plateforme puis confirmez l’envoi avec sa référence.", "En cas de rejet, indiquez le motif ; le solde réservé est restauré."],
      related: [{ href: "/dashboard/finance#retraits", label: "Synthèse des retraits" }, { href: "/dashboard/users", label: "Dossier du bénéficiaire" }],
    },
  ] },
  { id: "growth", label: "Communication et activité", pages: [
    {
      href: "/dashboard/promotions", label: "Offres et communications", Icon: Tag,
      description: "Créez les réductions, les communications dans l’application et les règles de parrainage.", keywords: "promotion campagne marketing parrainage bonus prime audience",
      steps: ["Choisissez la section : réduction, communication ou parrainage.", "Vérifiez les destinataires, les conditions, les dates et les limites avant activation.", "Une communication peut être notifiée depuis sa propre section ; les primes de parrainage sont réglées hors plateforme."],
      related: [{ href: "/dashboard/notifications", label: "Envoyer un message ponctuel" }, { href: "/dashboard/configuration#recompenses", label: "Régler les bonus de performance" }],
      sections: [{ id: "offres", label: "Réductions" }, { id: "communications", label: "Communications" }, { id: "parrainage", label: "Conditions du parrainage" }, { id: "primes", label: "Paiement des primes" }, { id: "statistiques", label: "Résultats du parrainage" }],
    },
    {
      href: "/dashboard/notifications", label: "Messages aux utilisateurs", Icon: Bell,
      description: "Envoyez un message ponctuel aux utilisateurs sélectionnés et consultez l’historique.", keywords: "notification ciblée push message envoi destinataires",
      steps: ["Sélectionnez les destinataires : ce sont les utilisateurs de l’application, pas les administrateurs.", "Rédigez le message et vérifiez son lien de destination.", "Contrôlez la sélection avant l’envoi et consultez ensuite l’historique."],
      related: [{ href: "/dashboard/promotions#communications", label: "Communications avec visuel" }, { href: "/dashboard/settings/alerts", label: "Mes alertes administrateur" }],
    },
    {
      href: "/dashboard/performances", label: "Performances et objectifs", Icon: Trophy,
      description: "Comparez les classements, les objectifs et les récompenses des clients et partenaires.", keywords: "fidélité classement gain bonus livreur relais",
      steps: ["Choisissez la période et le type de compte à consulter.", "Ouvrez un compte pour examiner son activité.", "Les conditions des bonus se règlent dans Configuration, pas dans les classements."],
      related: [{ href: "/dashboard/configuration#recompenses", label: "Configurer les récompenses" }, { href: "/dashboard/analytics", label: "Analyser l’activité" }],
    },
    {
      href: "/dashboard/analytics", label: "Analyses de l’activité", Icon: BarChart3,
      description: "Comparez les volumes, les délais, les modes de livraison et la qualité sur une période.", keywords: "statistiques indicateurs analyse rapport performance",
      steps: ["Définissez les dates de début et de fin.", "Comparez les délais et les résultats par mode de livraison.", "Utilisez la synthèse financière pour examiner les règlements et les soldes."],
      related: [{ href: "/dashboard/finance", label: "Synthèse financière" }, { href: "/dashboard/heatmap", label: "Répartition géographique" }],
    },
    {
      href: "/dashboard/heatmap", label: "Carte des demandes", Icon: Map,
      description: "Repérez les zones de demande et retrouvez les colis qui les composent.", keywords: "heatmap géocodage adresse carte chaleur zone quartier",
      steps: ["Choisissez la période et les filtres à appliquer.", "Sélectionnez une zone pour consulter ses adresses et les colis concernés.", "Les données de demande ne représentent pas les positions actuelles des livreurs."],
      related: [{ href: "/dashboard/fleet", label: "Positions des livreurs" }, { href: "/dashboard/relays", label: "Réseau des relais" }],
    },
  ] },
  { id: "control", label: "Contrôle et conformité", pages: [
    {
      href: "/dashboard/anomalies", label: "Anomalies opérationnelles", Icon: AlertTriangle, badge: "anomalies",
      description: "Contrôlez les pertes de signal et les missions qui dépassent les délais attendus.", keywords: "gps retard incident signal perdu",
      steps: ["Lisez le motif et l’ancienneté de l’anomalie.", "Ouvrez le contrôle pour vérifier la mission ou le colis.", "Contactez le livreur si nécessaire ; une perte de signal seule ne prouve pas un incident."],
      related: [{ href: "/dashboard/fleet", label: "Vérifier sur la carte" }, { href: "/dashboard/security", label: "Événements de sécurité" }],
    },
    {
      href: "/dashboard/security", label: "Sécurité des livreurs", Icon: AlertTriangle, badge: "security",
      description: "Examinez les blocages GPS et les événements de protection des missions.", keywords: "sécurité fraude protection localisation",
      steps: ["Filtrez la période et le type d’événement.", "Vérifiez les éléments du dossier avant toute intervention.", "Consultez le journal des actions pour retrouver les opérations déjà effectuées."],
      related: [{ href: "/dashboard/drivers", label: "Dossiers livreurs" }, { href: "/dashboard/audit-log", label: "Historique des actions" }],
    },
    {
      href: "/dashboard/privacy-requests", label: "Demandes de données", Icon: UserRoundCog,
      description: "Suivez les demandes des utilisateurs concernant leurs données personnelles.", keywords: "confidentialité accès export suppression rectification droits",
      steps: ["Vérifiez le demandeur, la nature de sa demande et son statut.", "Consultez le dossier utilisateur pour préparer une réponse adaptée.", "Enregistrez la réponse et actualisez le statut après traitement."],
      related: [{ href: "/dashboard/users", label: "Dossiers utilisateurs" }, { href: "/dashboard/legal", label: "Documents juridiques" }],
    },
    {
      href: "/dashboard/legal", label: "Documents juridiques", Icon: Scale,
      description: "Gérez les conditions générales, la confidentialité et le suivi de lecture.", keywords: "juridique cgu politique document consultation version",
      steps: ["Choisissez le document et vérifiez sa version et son contenu.", "Publiez les informations dans les champs prévus par cet écran.", "Consultez le suivi de lecture pour distinguer les utilisateurs informés de ceux qui ont consulté le document."],
      related: [{ href: "/dashboard/privacy-requests", label: "Demandes des utilisateurs" }, { href: "/dashboard/audit-log", label: "Journal des actions" }],
    },
    {
      href: "/dashboard/audit-log", label: "Journal des actions", Icon: History,
      description: "Retrouvez les événements et les interventions enregistrées dans Denkma.", keywords: "audit log historique trace événement administrateur",
      steps: ["Filtrez par période et recherchez le dossier ou l’événement.", "Examinez la date, l’auteur et les détails de l’action.", "Le journal explique ce qui a été enregistré ; les corrections se font dans le dossier concerné."],
      related: [{ href: "/dashboard/parcels", label: "Dossiers colis" }, { href: "/dashboard/users", label: "Dossiers utilisateurs" }],
    },
  ] },
  { id: "settings", label: "Réglages", pages: [
    {
      href: "/dashboard/configuration", label: "Configuration", Icon: Settings,
      description: "Réglez les tarifs, les commissions, les règles de livraison et les fonctionnalités proposées.", keywords: "paramètres taux express logistique diffusion bonus vidéo mise à jour",
      steps: ["Utilisez les accès aux sections pour retrouver le réglage voulu.", "Chaque bloc précise son bouton de sauvegarde : tarifs et livraison partagent une sauvegarde, les autres blocs sont indépendants.", "Vérifiez les valeurs et les effets indiqués avant de sauvegarder."],
      related: [{ href: "/dashboard/promotions", label: "Offres et parrainage" }, { href: "/dashboard/settings/alerts", label: "Mes alertes admin" }],
      sections: [{ id: "tarifs", label: "Tarifs" }, { id: "commissions", label: "Commissions" }, { id: "livraison", label: "Livraison et relais" }, { id: "diffusion", label: "Diffusion des courses" }, { id: "recompenses", label: "Récompenses" }, { id: "guide", label: "Vidéo explicative" }, { id: "mises-a-jour", label: "Mises à jour" }],
    },
    {
      href: "/dashboard/settings/alerts", label: "Mes alertes admin", Icon: BellRing,
      description: "Choisissez les événements qui vous notifient dans le navigateur.", keywords: "notifications administrateur son navigateur cloche préférences",
      steps: ["Autorisez les notifications du navigateur si vous souhaitez les recevoir.", "Choisissez les événements et les préférences proposés sur cet écran.", "Ces réglages ne créent aucun message pour les utilisateurs ; la cloche admin reste disponible."],
      related: [{ href: "/dashboard", label: "Actions à traiter" }, { href: "/dashboard/notifications", label: "Messages aux utilisateurs" }],
    },
  ] },
];

export const ADMIN_PAGES = [ADMIN_HOME, ...ADMIN_NAVIGATION.flatMap((group) => group.pages)];

export function adminPageForPath(path: string): AdminPage | undefined {
  const pathname = path.split(/[?#]/)[0].replace(/\/$/, "");
  return ADMIN_PAGES.find((page) => pathname === page.href) ??
    ADMIN_PAGES.find((page) => Boolean(page.detailLabel) && pathname.startsWith(`${page.href}/`));
}

function normalizeSearch(value: string) {
  return value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("fr");
}

export function searchAdminNavigation(query: string): AdminNavigationGroup[] {
  const words = normalizeSearch(query).trim().split(/\s+/).filter(Boolean);
  const groups = [{ id: "home", label: "Vue d’ensemble", pages: [ADMIN_HOME] }, ...ADMIN_NAVIGATION];
  return groups.map((group) => ({
    ...group,
    pages: group.pages.filter((page) => {
      const text = normalizeSearch(`${group.label} ${page.label} ${page.description} ${page.keywords ?? ""}`);
      return words.every((word) => text.includes(word));
    }),
  })).filter((group) => group.pages.length > 0);
}
