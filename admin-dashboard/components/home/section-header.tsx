import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { Button } from "@/components/ui/button";

type SectionHeaderProps = {
  title: string;
  subtitle: string;
  href: string;
};

export function SectionHeader({ title, subtitle, href }: SectionHeaderProps) {
  return (
    <div className="mb-4 flex items-end justify-between gap-4">
      <div className="min-w-0">
        <h2 className="text-xl font-black tracking-normal text-slate-950 sm:text-2xl">{title}</h2>
        <p className="mt-1 text-sm leading-6 text-slate-600 sm:text-base">{subtitle}</p>
      </div>
      <Button asChild variant="outline" size="sm" className="shrink-0">
        <Link href={href}>
          Voir tout
          <ArrowRight className="h-4 w-4" />
        </Link>
      </Button>
    </div>
  );
}
