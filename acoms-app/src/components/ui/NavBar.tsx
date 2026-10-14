"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { LogoutButton } from "./LogoutButton";

const LINKS = [
  { href: "/dashboard", label: "Dashboard" },
  { href: "/transfers", label: "Transfers" },
  { href: "/damage-loss", label: "Damage & Loss" },
  { href: "/reports", label: "Reports" },
];

// Two levels (ACOMS-DESIGN-001 7.1): identity bar on top, primary tabs below.
export function NavBar({ userName, showAdmin }: { userName?: string | null; showAdmin?: boolean }) {
  const pathname = usePathname();
  const links = showAdmin ? [...LINKS, { href: "/admin", label: "Admin" }] : LINKS;

  return (
    <header className="border-b border-(--color-header-border)">
      <div className="bg-(--color-header-bg)">
        <div className="mx-auto grid max-w-7xl grid-cols-[1fr_auto] items-center gap-x-3 px-3 py-2 sm:px-6">
          <Link
            href="/dashboard"
            aria-label="ACOMS, Airline Catering Operations Management System, dashboard"
            className="text-[1.65rem] font-bold leading-tight tracking-tight text-(--color-header-text) sm:text-[1.8rem]"
          >
            ACOMS
          </Link>
          {/* Always the right-hand cell of the first row, so it stays right-aligned at every width. */}
          <div className="col-start-2 row-start-1 flex items-center justify-end gap-0.5 text-(--color-header-text) sm:row-span-2 sm:gap-1">
            {userName && <span className="mr-1 hidden max-w-40 truncate text-sm sm:inline">{userName}</span>}
            <Link
              href="/settings"
              className="inline-flex min-h-11 items-center rounded-md px-2.5 text-sm font-medium hover:bg-(--color-header-hover) sm:px-3"
            >
              Settings
            </Link>
            <LogoutButton />
          </div>
          <p className="col-span-2 -mt-0.5 text-xs leading-snug text-(--color-header-text-muted) sm:col-span-1 sm:text-[0.8125rem]">
            Airline Catering Operations Management System
          </p>
        </div>
      </div>
      <nav aria-label="Primary" className="border-t border-(--color-header-border) bg-(--color-surface)">
        <ul className="mx-auto flex max-w-7xl gap-1 overflow-x-auto px-3 sm:justify-center sm:px-6">
          {links.map((link) => {
            const active = pathname === link.href || pathname.startsWith(link.href + "/");
            return (
              <li key={link.href} className="shrink-0">
                <Link
                  href={link.href}
                  aria-current={active ? "page" : undefined}
                  className={`inline-flex min-h-12 items-center border-b-2 px-5 text-base ${
                    active
                      ? "border-(--color-primary) bg-(--color-primary-soft) font-semibold text-(--color-on-primary-soft)"
                      : "border-transparent font-medium text-(--color-text-muted) hover:text-(--color-text)"
                  }`}
                >
                  {link.label}
                </Link>
              </li>
            );
          })}
        </ul>
      </nav>
    </header>
  );
}
