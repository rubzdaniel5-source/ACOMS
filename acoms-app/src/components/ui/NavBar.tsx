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
        <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-x-4 gap-y-1 px-3 py-2 sm:px-6">
          <Link href="/dashboard" className="flex flex-col leading-tight text-(--color-header-text)" aria-label="ACOMS, Airline Catering Operations Management System, dashboard">
            <span className="text-[1.65rem] font-bold tracking-tight sm:text-[1.8rem]">ACOMS</span>
            <span className="text-xs text-(--color-header-text-muted) sm:text-[0.8125rem]">
              Airline Catering Operations Management System
            </span>
          </Link>
          <div className="flex items-center gap-1 text-(--color-header-text)">
            {userName && (
              <span className="mr-1 hidden max-w-40 truncate text-sm sm:inline">{userName}</span>
            )}
            <Link
              href="/settings"
              className="inline-flex min-h-11 items-center rounded-md px-3 text-sm font-medium hover:bg-(--color-header-hover)"
            >
              Settings
            </Link>
            <LogoutButton />
          </div>
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
                  className={`inline-flex min-h-11 items-center border-b-2 px-4 text-sm ${
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
