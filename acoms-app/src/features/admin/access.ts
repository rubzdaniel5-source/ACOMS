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
    href: "/admin/users",
    label: "Users",
    description: "Create accounts, assign roles and stations, reset passwords, deactivate leavers.",
    anyOf: ["manage_users"],
  },
  {
    href: "/admin/roles",
    label: "Roles & Permissions",
    description: "See and edit what each role is allowed to do.",
    anyOf: ["manage_roles", "manage_users"],
  },
  {
    href: "/admin/catalogue",
    label: "Equipment Catalogue",
    description: "Add and edit equipment, stock levels, tolerances and aliases; import from CSV.",
    anyOf: ["manage_catalogue"],
  },
  {
    href: "/admin/data-quality",
    label: "Data Quality",
    description: "Replace placeholder equipment codes with confirmed ones.",
    anyOf: ["manage_catalogue"],
  },
  {
    href: "/admin/stations",
    label: "Stations",
    description: "Add stations and set whether each one holds stock.",
    anyOf: ["manage_configuration"],
  },
  {
    href: "/admin/stock-levels",
    label: "Station Stock Levels",
    description: "Set reorder thresholds and stock levels separately for each station.",
    anyOf: ["manage_catalogue"],
  },
  {
    href: "/admin/adjustments",
    label: "Stock Adjustments",
    description: "Request corrections to stock; a second person approves before the ledger changes.",
    anyOf: ["request_adjustment", "approve_adjustment"],
  },
  {
    href: "/admin/settings",
    label: "System Settings",
    description: "Edit the rules behind stock alerts, overdue transfers and default tolerances.",
    anyOf: ["manage_configuration"],
  },
  {
    href: "/admin/ledger",
    label: "Inventory Ledger",
    description: "Every stock movement ever recorded, with who did it and why.",
    anyOf: ["view_inventory"],
  },
];

/** Permission codes that make the Admin area visible at all. */
export const ADMIN_ENTRY_PERMISSIONS = ["record_opening_balance", "manage_users", "manage_roles", "manage_catalogue", "manage_configuration", "request_adjustment", "approve_adjustment"];

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
