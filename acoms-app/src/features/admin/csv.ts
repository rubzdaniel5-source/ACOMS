/** Minimal RFC-4180 style CSV parser (quoted fields, escaped quotes, CRLF). Client-safe. */
export function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let inQuotes = false;
  const src = text.replace(/^﻿/, "");
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (inQuotes) {
      if (c === '"') {
        if (src[i + 1] === '"') { field += '"'; i++; } else inQuotes = false;
      } else field += c;
    } else if (c === '"') inQuotes = true;
    else if (c === ",") { row.push(field); field = ""; }
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && src[i + 1] === "\n") i++;
      row.push(field); field = "";
      if (row.some((f) => f.trim() !== "")) rows.push(row);
      row = [];
    } else field += c;
  }
  row.push(field);
  if (row.some((f) => f.trim() !== "")) rows.push(row);
  return rows;
}

const HEADER_ALIASES: Record<string, string> = {
  code: "source_code", item_code: "source_code", "source code": "source_code",
  item: "name", description_short: "name", unit: "unit_of_measure", uom: "unit_of_measure",
  tolerance: "reconciliation_tolerance", tracking: "tracking_method",
};
const NUMERIC = new Set(["pack_size", "reorder_threshold", "minimum_stock", "target_stock", "maximum_stock", "reconciliation_tolerance"]);
const BOOLEAN = new Set(["is_consumable", "is_returnable"]);

export const IMPORT_COLUMNS = [
  "source_code", "name", "category", "description", "unit_of_measure", "packaging_unit", "pack_size",
  "tracking_method", "is_consumable", "is_returnable", "reorder_threshold", "minimum_stock",
  "target_stock", "maximum_stock", "reconciliation_tolerance", "ownership_type", "notes",
];

/** Converts CSV text into import rows. Empty cells are omitted so they mean "no change". */
export function csvToImportRows(text: string): { rows: Record<string, unknown>[]; error?: string } {
  const table = parseCsv(text);
  if (table.length < 2) return { rows: [], error: "The file needs a header row and at least one data row." };
  const headers = table[0].map((h) => {
    const k = h.trim().toLowerCase();
    return HEADER_ALIASES[k] ?? k.replace(/\s+/g, "_");
  });
  for (const req of ["source_code", "name", "category"]) {
    if (!headers.includes(req)) return { rows: [], error: `Missing required column: ${req}` };
  }
  const rows = table.slice(1).map((cells) => {
    const o: Record<string, unknown> = {};
    headers.forEach((h, i) => {
      if (!IMPORT_COLUMNS.includes(h)) return;
      const v = (cells[i] ?? "").trim();
      if (v === "") return;
      if (BOOLEAN.has(h)) o[h] = ["true", "yes", "y", "1"].includes(v.toLowerCase());
      else if (NUMERIC.has(h)) o[h] = v;
      else if (h === "tracking_method") o[h] = v.toUpperCase();
      else o[h] = v;
    });
    return o;
  });
  return { rows };
}
