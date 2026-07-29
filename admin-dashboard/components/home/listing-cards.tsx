import { BadgeCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";

type BaseListing = {
  image?: string;
  category: string;
  city: string;
  price?: string;
  verified?: boolean;
};

export type RealEstateListing = BaseListing & {
  title: string;
  district?: string;
};

export type HotelListing = BaseListing & {
  name: string;
  rating?: string;
};

export type VehicleListing = BaseListing & {
  brand: string;
  model: string;
  transmission?: string;
  fuel?: string;
};

export type TripListing = {
  departureCity: string;
  arrivalCity: string;
  transportType: string;
  priceFrom?: string;
  company?: string;
  departureTime?: string;
  verified?: boolean;
};

function VerifiedBadge({ visible }: { visible?: boolean }) {
  if (!visible) return null;

  return (
    <span className="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2 py-1 text-xs font-bold text-emerald-700">
      <BadgeCheck className="h-3.5 w-3.5" />
      Vérifié
    </span>
  );
}

function ListingShell({ children }: { children: React.ReactNode }) {
  return <Card className="min-w-[30%] max-w-[30%] rounded-lg p-3 shadow-sm sm:min-w-64 sm:max-w-64">{children}</Card>;
}

export function RealEstateCard({ listing }: { listing: RealEstateListing }) {
  return (
    <ListingShell>
      <div className="space-y-2">
        <VerifiedBadge visible={listing.verified} />
        <p className="text-xs font-bold uppercase tracking-normal text-blue-700">{listing.category}</p>
        <h3 className="text-sm font-black text-slate-950">{listing.title}</h3>
        <p className="text-xs text-slate-500">{[listing.city, listing.district].filter(Boolean).join(", ")}</p>
        <p className="text-sm font-black text-slate-950">{listing.price}</p>
        <Button size="sm" className="w-full">Voir détails</Button>
      </div>
    </ListingShell>
  );
}

export function HotelCard({ listing }: { listing: HotelListing }) {
  return (
    <ListingShell>
      <div className="space-y-2">
        <VerifiedBadge visible={listing.verified} />
        <p className="text-xs font-bold uppercase tracking-normal text-blue-700">{listing.category}</p>
        <h3 className="text-sm font-black text-slate-950">{listing.name}</h3>
        <p className="text-xs text-slate-500">{listing.city}</p>
        <p className="text-sm font-black text-slate-950">{listing.price}</p>
        <p className="text-xs text-slate-500">{listing.rating}</p>
        <Button size="sm" className="w-full">Voir détails</Button>
      </div>
    </ListingShell>
  );
}

export function VehicleCard({ listing }: { listing: VehicleListing }) {
  return (
    <ListingShell>
      <div className="space-y-2">
        <VerifiedBadge visible={listing.verified} />
        <p className="text-xs font-bold uppercase tracking-normal text-blue-700">{listing.category}</p>
        <h3 className="text-sm font-black text-slate-950">{listing.brand} {listing.model}</h3>
        <p className="text-xs text-slate-500">{listing.city}</p>
        <p className="text-sm font-black text-slate-950">{listing.price}</p>
        <p className="text-xs text-slate-500">{[listing.transmission, listing.fuel].filter(Boolean).join(" · ")}</p>
        <Button size="sm" className="w-full">Voir détails</Button>
      </div>
    </ListingShell>
  );
}

export function TripCard({ listing }: { listing: TripListing }) {
  return (
    <ListingShell>
      <div className="space-y-2">
        <VerifiedBadge visible={listing.verified} />
        <p className="text-xs font-bold uppercase tracking-normal text-blue-700">{listing.transportType}</p>
        <h3 className="text-sm font-black text-slate-950">{listing.departureCity} → {listing.arrivalCity}</h3>
        <p className="text-xs text-slate-500">{listing.company}</p>
        <p className="text-sm font-black text-slate-950">{listing.priceFrom}</p>
        <p className="text-xs text-slate-500">{listing.departureTime}</p>
        <Button size="sm" className="w-full">Voir détails</Button>
      </div>
    </ListingShell>
  );
}
