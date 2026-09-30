"use client";

import * as React from "react";
import { adminPageForPath } from "@/lib/admin-navigation";
import { cn } from "@/lib/utils";

export function PageSectionNav({ page, hiddenSections = [] }: { page: string; hiddenSections?: string[] }) {
  const sections = adminPageForPath(page)?.sections?.filter((section) => !hiddenSections.includes(section.id)) ?? [];
  const sectionIds = sections.map((section) => section.id).join(",");
  const [active, setActive] = React.useState("");
  React.useEffect(() => {
    const update = () => setActive(window.location.hash.slice(1));
    update();
    const target = window.location.hash.slice(1);
    if (target && sectionIds.split(",").includes(target)) {
      document.getElementById(target)?.scrollIntoView({ block: "start" });
    }
    window.addEventListener("hashchange", update);
    return () => window.removeEventListener("hashchange", update);
  }, [sectionIds]);
  if (sections.length === 0) return null;
  return (
    <nav aria-label="Sections de cet écran" className="sticky top-16 z-20 -mx-1 rounded-lg border bg-background/95 p-2 shadow-sm backdrop-blur">
      <div className="flex items-center gap-2 overflow-x-auto">
        <span className="shrink-0 px-2 text-xs font-medium text-muted-foreground">Accès rapide</span>
        {sections.map((section) => <a key={section.id} href={`#${section.id}`} onClick={() => setActive(section.id)} aria-current={active === section.id ? "location" : undefined}
          className={cn("shrink-0 rounded-md px-3 py-2 text-xs font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring", active === section.id ? "bg-primary/10 text-primary" : "text-muted-foreground hover:bg-accent hover:text-foreground")}>{section.label}</a>)}
      </div>
    </nav>
  );
}
