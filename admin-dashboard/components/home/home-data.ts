import {
  Building2,
  Bus,
  Car,
  Hotel,
  LucideIcon,
  MessageCircle,
  Search,
  ShieldCheck,
} from "lucide-react";

export type Category = {
  title: string;
  description: string;
  actionLabel: string;
  href: string;
  icon: LucideIcon;
};

export const mainNavigation = [
  { label: "Immobilier", href: "/immobilier" },
  { label: "Hôtels", href: "/hotels" },
  { label: "Voitures", href: "/voitures" },
  { label: "Voyages interurbains", href: "/voyages" },
];

export const accountLinks = [
  { label: "Se connecter", href: "/login", variant: "ghost" as const },
  { label: "Créer mon espace", href: "/register", variant: "outline" as const },
  { label: "Publier une annonce", href: "/login?next=/publier", variant: "default" as const },
];

export const quickSuggestions = [
  "Appartement à Dakar",
  "Hôtel à Saly",
  "Toyota Prado",
  "Dakar Touba",
];

export const categories: Category[] = [
  {
    title: "Immobilier",
    description: "Louer, acheter ou vendre une maison, un appartement, un terrain ou un studio au Sénégal.",
    actionLabel: "Voir les biens",
    href: "/immobilier",
    icon: Building2,
  },
  {
    title: "Hôtels & Auberges",
    description: "Réserver un hôtel, une auberge, une résidence ou un appartement meublé.",
    actionLabel: "Trouver un séjour",
    href: "/hotels",
    icon: Hotel,
  },
  {
    title: "Voitures",
    description: "Louer, acheter ou vendre une voiture avec ou sans chauffeur.",
    actionLabel: "Voir les voitures",
    href: "/voitures",
    icon: Car,
  },
  {
    title: "Voyages interurbains",
    description: "Trouver un trajet entre les villes du Sénégal : bus, car, minibus ou 7 places.",
    actionLabel: "Chercher un trajet",
    href: "/voyages",
    icon: Bus,
  },
];

export const listingSections = [
  {
    title: "Immobilier",
    subtitle: "Maisons, appartements, terrains et studios à découvrir.",
    href: "/immobilier",
    emptyMessage: "Aucune annonce immobilière disponible pour le moment.",
    items: [],
  },
  {
    title: "Hôtels & Auberges",
    subtitle: "Hôtels, auberges, résidences et séjours partout au Sénégal.",
    href: "/hotels",
    emptyMessage: "Aucun hébergement disponible pour le moment.",
    items: [],
  },
  {
    title: "Voitures",
    subtitle: "Voitures à louer, à acheter ou avec chauffeur.",
    href: "/voitures",
    emptyMessage: "Aucune voiture disponible pour le moment.",
    items: [],
  },
  {
    title: "Voyages interurbains",
    subtitle: "Trajets entre les villes du Sénégal : bus, car, minibus ou 7 places.",
    href: "/voyages",
    emptyMessage: "Aucun trajet disponible pour le moment.",
    items: [],
  },
] satisfies Array<{
  title: string;
  subtitle: string;
  href: string;
  emptyMessage: string;
  items: unknown[];
}>;

export const advantages = [
  {
    title: "Offres organisées",
    text: "Retrouvez les annonces par univers : immobilier, hôtels, voitures et voyages interurbains.",
    icon: ShieldCheck,
  },
  {
    title: "Recherche simple",
    text: "Trouvez rapidement une offre selon votre ville, votre budget ou votre besoin.",
    icon: Search,
  },
  {
    title: "Mise en relation directe",
    text: "Contactez les annonceurs selon les moyens qu’ils ont activés.",
    icon: MessageCircle,
  },
];

export const professionalBenefits = [
  "Publier vos annonces",
  "Recevoir des demandes",
  "Discuter avec les clients",
  "Choisir vos moyens de contact",
];

export const footerColumns = [
  {
    title: "Univers",
    links: mainNavigation,
  },
  {
    title: "Professionnels",
    links: [
      { label: "Publier une annonce", href: "/login?next=/publier" },
      { label: "Espace partenaire", href: "/login?next=/dashboard" },
      { label: "Se connecter", href: "/login" },
      { label: "Aide", href: "/aide" },
    ],
  },
  {
    title: "Informations",
    links: [
      { label: "Conditions d’utilisation", href: "/conditions" },
      { label: "Confidentialité", href: "/confidentialite" },
      { label: "Mentions légales", href: "/mentions-legales" },
      { label: "Contact", href: "/contact" },
    ],
  },
];
