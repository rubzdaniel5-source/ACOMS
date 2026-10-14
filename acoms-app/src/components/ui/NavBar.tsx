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
    <header className="border-b border-(--color-border) bg-(--color-surface)">
      <div className="mx-auto flex max-w-7xl items-center justify-between gap-3 px-3 py-2 sm:px-6">
        <Link href="/dashboard" className="id-code text-base font-semibold tracking-wide text-(--color-text)">
          ACOMS
          <span className="ml-2 hidden text-xs font-normal text-(--color-text-subtle) sm:inline">
            Airline Catering Operations
          </span>
        </Link>
        <div className="flex items-center gap-1 sm:gap-3">
          {userName && (
            <span className="hidden max-w-40 truncate text-sm text-(--color-text-muted) sm:inline">{userName}</span>
          )}
          <Link
            href="/settings"
            className="inline-flex min-h-11 items-center rounded-md px-2 text-sm font-medium text-(--color-text-muted) hover:bg-(--color-surface-hover) hover:text-(--color-text)"
          >
            Settings
          </Link>
          <LogoutButton />
        </div>
      </div>
      <nav aria-label="Primary" className="border-t border-(--color-border) bg-(--color-surface-subtle)">
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
