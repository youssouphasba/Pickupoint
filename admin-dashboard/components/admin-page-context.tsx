"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ArrowRight, ChevronRight, HelpCircle } from "lucide-react";
import { ADMIN_NAVIGATION, adminPageForPath } from "@/lib/admin-navigation";

export function AdminBreadcrumbs() {
  const pathname = usePathname();
  const page = adminPageForPath(pathname);
  if (!page) return null;
  const group = ADMIN_NAVIGATION.find((entry) => entry.pages.some((item) => item.href === page.href));
  const detail = pathname !== page.href && Boolean(page.detailLabel);
  return (
    <nav aria-label="Fil d’Ariane" className="min-w-0 text-sm">
      <ol className="flex min-w-0 items-center gap-2">
        <li className="hidden shrink-0 text-muted-foreground xl:block">{group?.label ?? "Denkma"}</li>
        <li className="hidden xl:block"><ChevronRight className="h-3.5 w-3.5 text-muted-foreground" aria-hidden="true" /></li>
        <li className="min-w-0 truncate">
          {detail ? <Link href={page.href} className="text-muted-foreground hover:text-primary hover:underline">{page.label}</Link> : <span aria-current="page" className="font-medium">{page.label}</span>}
        </li>
        {detail && <><li><ChevronRight className="h-3.5 w-3.5 text-muted-foreground" aria-hidden="true" /></li><li className="min-w-0 truncate font-medium" aria-current="page">{page.detailLabel}</li></>}
      </ol>
    </nav>
  );
}

export function AdminPageContext() {
  const pathname = usePathname();
  const page = adminPageForPath(pathname);
  if (!page) return null;
  const detail = pathname !== page.href && Boolean(page.detailLabel);
  return (
    <div className="border-b bg-background px-4 py-3 sm:px-6 lg:px-8">
      <div className="flex flex-wrap items-center justify-between gap-x-5 gap-y-3">
        <nav aria-label="Accès complémentaires" className="flex flex-wrap gap-x-5 gap-y-2 text-xs">
          {detail && <Link href={page.href} className="font-medium text-primary hover:underline">Retour à la liste</Link>}
          {page.related.map((link) => <Link key={link.href} href={link.href} className="inline-flex items-center gap-1 font-medium text-muted-foreground hover:text-primary hover:underline">{link.label}<ArrowRight className="h-3 w-3 shrink-0" aria-hidden="true" /></Link>)}
        </nav>
        {!detail && <details key={page.href} className="group w-full sm:w-auto sm:[&[open]]:w-full">
          <summary className="flex cursor-pointer list-none items-center gap-1.5 text-xs font-medium text-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"><HelpCircle className="h-4 w-4" aria-hidden="true" />À quoi sert cet écran ?</summary>
          <div className="mt-3 rounded-lg border bg-muted/20 p-4 text-sm">
            <p className="font-medium">{page.description}</p>
            <ol className="mt-3 grid gap-3 lg:grid-cols-3">
              {page.steps.map((step, index) => <li key={step} className="flex items-start gap-2 text-muted-foreground"><span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-primary/10 text-xs font-semibold text-primary">{index + 1}</span><span>{step}</span></li>)}
            </ol>
          </div>
        </details>}
      </div>
    </div>
  );
}
