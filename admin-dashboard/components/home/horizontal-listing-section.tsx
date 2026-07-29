import { EmptyState } from "./empty-state";
import { SectionHeader } from "./section-header";

type HorizontalListingSectionProps<T> = {
  title: string;
  subtitle: string;
  href: string;
  emptyMessage: string;
  items: T[];
  renderItem?: (item: T) => React.ReactNode;
};

export function HorizontalListingSection<T>({
  title,
  subtitle,
  href,
  emptyMessage,
  items,
  renderItem,
}: HorizontalListingSectionProps<T>) {
  return (
    <section className="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
      <SectionHeader title={title} subtitle={subtitle} href={href} />
      {items.length === 0 || !renderItem ? (
        <EmptyState message={emptyMessage} />
      ) : (
        <div className="flex gap-3 overflow-x-auto pb-2 [scrollbar-width:thin]">
          {items.map((item, index) => (
            <div key={index} className="shrink-0">
              {renderItem(item)}
            </div>
          ))}
        </div>
      )}
    </section>
  );
}
