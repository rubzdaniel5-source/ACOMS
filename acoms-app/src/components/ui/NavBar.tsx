import Link from "next/link";

const LINKS = [
  { href: "/dashboard", label: "Dashboard" },
  { href: "/transfers", label: "Transfers" },
  { href: "/damage-loss", label: "Damage & Loss" },
];

export function NavBar() {
  return (
    <nav className="border-b border-slate-200 bg-white">
      <div className="mx-auto flex max-w-6xl items-center gap-6 px-4 py-3">
        <span className="text-sm font-semibold text-slate-900">ACOMS</span>
        {LINKS.map((link) => (
          <Link
            key={link.href}
            href={link.href}
            className="text-sm font-medium text-slate-600 hover:text-slate-900"
          >
            {link.label}
          </Link>
        ))}
      </div>
    </nav>
  );
}
