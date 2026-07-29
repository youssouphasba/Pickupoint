import { AdvantagesSection } from "@/components/home/advantages-section";
import { CategoryGrid } from "@/components/home/category-grid";
import { Footer } from "@/components/home/footer";
import { Header } from "@/components/home/header";
import { HeroSearch } from "@/components/home/hero-search";
import { listingSections } from "@/components/home/home-data";
import { HorizontalListingSection } from "@/components/home/horizontal-listing-section";
import { ProfessionalCTA } from "@/components/home/professional-cta";

export default function RootPage() {
  return (
    <main className="min-h-screen bg-slate-50 text-slate-950">
      <Header />
      <HeroSearch />
      <CategoryGrid />
      <div className="py-2">
        {listingSections.map((section) => (
          <HorizontalListingSection
            key={section.href}
            title={section.title}
            subtitle={section.subtitle}
            href={section.href}
            emptyMessage={section.emptyMessage}
            items={section.items}
          />
        ))}
      </div>
      <AdvantagesSection />
      <ProfessionalCTA />
      <Footer />
    </main>
  );
}
