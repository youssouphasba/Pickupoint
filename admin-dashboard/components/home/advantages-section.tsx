import { advantages } from "./home-data";

export function AdvantagesSection() {
  return (
    <section className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      <div className="grid gap-4 md:grid-cols-3">
        {advantages.map((advantage) => {
          const Icon = advantage.icon;

          return (
            <div key={advantage.title} className="rounded-lg border border-slate-200 bg-white p-5 shadow-sm">
              <div className="mb-4 flex h-10 w-10 items-center justify-center rounded-lg bg-sky-50 text-sky-700">
                <Icon className="h-5 w-5" />
              </div>
              <h2 className="text-base font-black text-slate-950">{advantage.title}</h2>
              <p className="mt-2 text-sm leading-6 text-slate-600">{advantage.text}</p>
            </div>
          );
        })}
      </div>
    </section>
  );
}
