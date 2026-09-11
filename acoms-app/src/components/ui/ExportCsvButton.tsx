"use client";

/**
 * Converts already-fetched rows to CSV and triggers a browser download.
 * Deliberately client-side and dumb: it exports exactly what the server
 * already returned. Since every query upstream goes through Supabase with
 * RLS applied, this never sees data the current user isn't authorized to
 * see (master spec §49 — exports must respect permissions/scope, not
 * bypass them).
 */
export function ExportCsvButton({ rows, filename }: { rows: Record<string, unknown>[]; filename: string }) {
  function handleExport() {
    if (rows.length === 0) return;

    const headers = Object.keys(rows[0]);
    const escape = (val: unknown) => {
      const s = val === null || val === undefined ? "" : String(val);
      return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
    };

    const csv = [
      headers.join(","),
      ...rows.map((row) => headers.map((h) => escape(row[h])).join(",")),
    ].join("\n");

    const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = filename;
    link.click();
    URL.revokeObjectURL(url);
  }

  return (
    <button
      onClick={handleExport}
      disabled={rows.length === 0}
      className="btn-secondary px-3 py-1.5 text-xs disabled:opacity-40"
    >
      Export CSV
    </button>
  );
}
