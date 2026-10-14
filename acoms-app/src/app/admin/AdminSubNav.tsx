"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

export function AdminSubNav({ sections }: { sections: { href: string; label: string }[] }) {
  const pathname = usePathname();
  const items = [{ href: "/admin", label: "Overview" }, ...sections];
  return (
    <nav className="flex flex-col gap-1">
      {items.map((s) => {
        const active = s.href === "/admin" ? pathname === "/admin" : pathname.startsWith(s.href);
        return (
          <Link
            key={s.href}
            href={s.href}
            className={`rounded-md px-3 py-2 text-base font-medium ${
              active ? "bg-(--color-action) text-(--color-on-action)" : "text-(--steel) hover:bg-(--steel-light)"
            }`}
          >
            {s.label}
          </Link>
        );
      })}
    </nav>
  );
}
