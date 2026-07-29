import { categories } from "./home-data";
import { CategoryCard } from "./category-card";

export function CategoryGrid() {
  return (
    <section className="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
      <div className="grid grid-cols-2 gap-3 md:gap-4 lg:grid-cols-4">
        {categories.map((category) => (
          <CategoryCard key={category.href} category={category} />
        ))}
      </div>
    </section>
  );
}
