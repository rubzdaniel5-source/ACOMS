import { redirect } from "next/navigation";
import { getCurrentUserPermissions } from "@/features/auth/permissions";

export type AdminSection = {
  href: string;
  label: string;
  description: string;
  /** Any one of these permissions grants visibility of the section. */
  anyOf: string[];
};

export const ADMIN_SECTIONS: AdminSection[] = [
  {
    href: "/admin/opening-balances",
    label: "Opening Balances",
    description: "Record the one-time starting stock for each station and equipment type.",
    anyOf: ["record_opening_balance"],
  },
  {
    href: "/admin/ledger",
    label: "Inventory Ledger",
    description: "Every stock movement ever recorded, with who did it and why.",
    anyOf: ["view_inventory"],
  },
];

/** Permission codes that make the Admin area visible at all. */
export const ADMIN_ENTRY_PERMISSIONS = ["record_opening_balance", "manage_users", "manage_catalogue", "manage_configuration"];

export function visibleSections(perms: Set<string>): AdminSection[] {
  return ADMIN_SECTIONS.filter((s) => s.anyOf.some((p) => perms.has(p)));
}

export function canEnterAdmin(perms: Set<string>): boolean {
  return ADMIN_ENTRY_PERMISSIONS.some((p) => perms.has(p));
}

/** Server-side page guard: redirects away unless the user holds one of the permissions. */
export async function requireAnyPermission(codes: string[]): Promise<Set<string>> {
  const perms = await getCurrentUserPermissions();
  if (!codes.some((c) => perms.has(c))) redirect("/admin");
  return perms;
}
