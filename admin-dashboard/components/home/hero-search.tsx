"use client";

import { FormEvent, useState } from "react";
import { Search } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { getSearchDestination } from "@/lib/home-search";
import { quickSuggestions } from "./home-data";

export function HeroSearch() {
  const [query, setQuery] = useState("");

  function runSearch(value: string) {
    const destination = getSearchDestination(value);
    window.location.assign(destination);
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    runSearch(query);
  }

  return (
    <section className="mx-auto max-w-5xl px-4 pb-8 pt-12 text-center sm:px-6 lg:px-8 lg:pb-12 lg:pt-16">
      <div className="mx-auto max-w-4xl">
        <div className="mb-4 inline-flex rounded-full border border-blue-100 bg-blue-50 px-3 py-1 text-xs font-bold uppercase tracking-normal text-blue-800">
          Portail sénégalais multiservices
        </div>
        <h1 className="text-4xl font-black leading-tight tracking-normal text-slate-950 sm:text-5xl lg:text-6xl">
          Trouvez un logement, un hôtel, une voiture ou un trajet au Sénégal
        </h1>
        <p className="mx-auto mt-5 max-w-2xl text-base leading-7 text-slate-600 sm:text-lg">
          Trouvez rapidement des offres de logement, d’hébergement, de voiture et de voyage partout au Sénégal.
        </p>
      </div>

      <form onSubmit={handleSubmit} className="mx-auto mt-8 max-w-4xl rounded-2xl border border-slate-200 bg-white p-2 shadow-xl shadow-blue-950/10">
        <div className="flex flex-col gap-2 sm:flex-row">
          <label className="sr-only" htmlFor="home-search">
            Que recherchez-vous ?
          </label>
          <div className="relative min-w-0 flex-1">
            <Search className="pointer-events-none absolute left-4 top-1/2 h-5 w-5 -translate-y-1/2 text-slate-400" />
            <Input
              id="home-search"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Que recherchez-vous ? Exemple : hôtel 5 étoiles, Toyota Prado, appartement à Dakar, Dakar Touba"
              className="h-12 rounded-xl border-0 bg-slate-50 pl-11 pr-4 text-base shadow-none focus-visible:ring-blue-600"
            />
          </div>
          <Button type="submit" className="h-12 rounded-xl bg-blue-700 px-6 text-white hover:bg-blue-800">
            Rechercher
          </Button>
        </div>
      </form>

      <div className="mx-auto mt-4 flex max-w-4xl flex-wrap justify-center gap-2">
        {quickSuggestions.map((suggestion) => (
          <button
            key={suggestion}
            type="button"
            onClick={() => runSearch(suggestion)}
            className="rounded-full border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-600 shadow-sm transition hover:border-blue-200 hover:bg-blue-50 hover:text-blue-800"
          >
            {suggestion === "Dakar Touba" ? "Dakar → Touba" : suggestion}
          </button>
        ))}
      </div>
    </section>
  );
}
