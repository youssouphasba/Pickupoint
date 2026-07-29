import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Category } from "./home-data";

export function CategoryCard({ category }: { category: Category }) {
  const Icon = category.icon;

  return (
    <Card className="group flex h-full flex-col justify-between rounded-lg border-slate-200 bg-white p-4 shadow-sm transition hover:-translate-y-1 hover:border-blue-200 hover:shadow-lg hover:shadow-blue-950/10">
      <div>
        <div className="mb-3 flex h-10 w-10 items-center justify-center rounded-lg bg-blue-50 text-blue-700">
          <Icon className="h-5 w-5" />
        </div>
        <h2 className="text-base font-black text-slate-950">{category.title}</h2>
        <p className="mt-2 line-clamp-4 text-sm leading-6 text-slate-600">{category.description}</p>
      </div>
      <Link href={category.href} className="mt-4 inline-flex items-center gap-2 text-sm font-bold text-blue-700 transition group-hover:text-blue-900">
        {category.actionLabel}
        <ArrowRight className="h-4 w-4" />
      </Link>
    </Card>
  );
}
