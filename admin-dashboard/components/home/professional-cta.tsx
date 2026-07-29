import Link from "next/link";
import { CheckCircle2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { professionalBenefits } from "./home-data";

export function ProfessionalCTA() {
  return (
    <section className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      <div className="overflow-hidden rounded-2xl bg-slate-950 p-6 text-white shadow-xl shadow-slate-950/15 sm:p-8 lg:p-10">
        <div className="grid gap-8 lg:grid-cols-[1.1fr_0.9fr] lg:items-center">
          <div>
            <h2 className="text-2xl font-black tracking-normal sm:text-3xl">Vous êtes agence, hôtel, loueur ou transporteur ?</h2>
            <p className="mt-3 max-w-2xl text-sm leading-7 text-slate-300 sm:text-base">
              Créez votre espace, publiez vos offres et gérez vos contacts depuis Péncmi.
            </p>
            <div className="mt-6 flex flex-col gap-3 sm:flex-row">
              <Button asChild className="bg-white text-slate-950 hover:bg-slate-100">
                <Link href="/register">Créer mon espace</Link>
              </Button>
              <Button asChild variant="outline" className="border-white/25 bg-transparent text-white hover:bg-white/10 hover:text-white">
                <Link href="/login?next=/publier">Publier une annonce</Link>
              </Button>
            </div>
          </div>
          <div className="grid gap-3 sm:grid-cols-2">
            {professionalBenefits.map((benefit) => (
              <div key={benefit} className="flex items-center gap-3 rounded-lg border border-white/10 bg-white/5 px-3 py-3 text-sm font-semibold text-slate-100">
                <CheckCircle2 className="h-5 w-5 shrink-0 text-amber-300" />
                {benefit}
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
