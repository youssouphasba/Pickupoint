import Link from "next/link";
import { footerColumns } from "./home-data";

export function Footer() {
  return (
    <footer className="mt-8 border-t border-slate-200 bg-white">
      <div className="mx-auto grid max-w-7xl gap-8 px-4 py-10 sm:px-6 md:grid-cols-2 lg:grid-cols-4 lg:px-8">
        <div>
          <h2 className="text-xl font-black text-slate-950">Péncmi</h2>
          <p className="mt-3 text-sm leading-6 text-slate-600">
            Portail sénégalais pour logement, hôtels, voitures et voyages interurbains.
          </p>
        </div>
        {footerColumns.map((column) => (
          <div key={column.title}>
            <h3 className="text-sm font-black text-slate-950">{column.title}</h3>
            <ul className="mt-3 space-y-2">
              {column.links.map((link) => (
                <li key={link.href}>
                  <Link href={link.href} className="text-sm text-slate-600 transition hover:text-blue-700">
                    {link.label}
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
      <div className="border-t border-slate-200 px-4 py-5 text-center text-sm text-slate-500">
        © 2026 Péncmi. Tous droits réservés.
      </div>
    </footer>
  );
}
