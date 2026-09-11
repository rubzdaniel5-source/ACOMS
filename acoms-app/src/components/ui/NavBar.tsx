import Link from "next/link";

const LINKS = [
  { href: "/dashboard", label: "Dashboard" },
  { href: "/transfers", label: "Transfers" },
  { href: "/damage-loss", label: "Damage & Loss" },
  { href: "/reports", label: "Reports" },
];

export function NavBar() {
  return (
    <nav className="bg-(--navy) text-white">
      <div className="mx-auto flex max-w-6xl items-center gap-8 px-4 py-3">
        <span className="id-code text-sm font-semibold tracking-wide">ACOMS</span>
        <div className="flex gap-6">
          {LINKS.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="text-sm font-medium text-white/75 hover:text-white"
            >
              {link.label}
            </Link>
          ))}
        </div>
      </div>
    </nav>
  );
}
