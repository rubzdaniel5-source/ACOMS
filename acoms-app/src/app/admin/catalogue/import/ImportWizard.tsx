"use client";

import { useState, useTransition } from "react";
import { applyImport, previewImport } from "../actions";
import { csvToImportRows, IMPORT_COLUMNS } from "@/features/admin/csv";

type PreviewRow = { row_number: number; source_code: string; action: string; error: string | null };

export function ImportWizard() {
  const [rows, setRows] = useState<Record<string, unknown>[]>([]);
  const [preview, setPreview] = useState<PreviewRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<number | null>(null);
  const [pending, startTransition] = useTransition();

  async function onFile(file: File | undefined) {
    setError(null); setPreview(null); setDone(null); setRows([]);
    if (!file) return;
    const parsed = csvToImportRows(await file.text());
    if (parsed.error) return setError(parsed.error);
    if (parsed.rows.length > 1000) return setError("Import at most 1000 rows at a time.");
    setRows(parsed.rows);
    startTransition(async () => {
      const res = await previewImport(parsed.rows);
      if (!res.ok) return setError(res.error);
      setPreview(res.rows);
    });
  }

  function confirmImport() {
    setError(null);
    startTransition(async () => {
      const res = await applyImport(rows);
      if (!res.ok) return setError(res.error);
      setDone(res.count); setPreview(null); setRows([]);
    });
  }

  function downloadTemplate() {
    const sample = [IMPORT_COLUMNS.join(","), "NEW-001,Example Tray,TRAYS,,EACH,,,QUANTITY,false,true,100,50,200,400,1,AIRLINE_OWNED,"].join("\n");
    const url = URL.createObjectURL(new Blob([sample], { type: "text/csv" }));
    const a = document.createElement("a"); a.href = url; a.download = "equipment-import-template.csv"; a.click(); URL.revokeObjectURL(url);
  }

  const errors = preview?.filter((p) => p.action === "error").length ?? 0;
  const creates = preview?.filter((p) => p.action === "create").length ?? 0;
  const updates = preview?.filter((p) => p.action === "update").length ?? 0;

  return (
    <div className="space-y-4">
      <div className="panel flex flex-wrap items-center gap-4 p-4">
        <input type="file" accept=".csv,text/csv" onChange={(e) => onFile(e.target.files?.[0])} className="text-sm" />
        <button className="btn-secondary px-3 py-1.5 text-sm" onClick={downloadTemplate}>Download template</button>
        <p className="text-xs text-(--steel)">Required columns: source_code, name, category (code or name).</p>
      </div>

      {error && <p className="rounded-sm px-3 py-2 text-sm text-(--brick)" style={{ background: "var(--brick-surface)" }}>{error}</p>}
      {done !== null && <p className="rounded-sm px-3 py-2 text-sm text-(--teal)" style={{ background: "var(--teal-surface)" }}>Imported {done} row{done === 1 ? "" : "s"}.</p>}

      {preview && (
        <div className="panel p-4">
          <p className="mb-3 text-sm">
            <span className="tag tag-teal">{creates} to create</span>{" "}
            <span className="tag tag-neutral">{updates} to update</span>{" "}
            {errors > 0 && <span className="tag tag-brick">{errors} with errors</span>}
          </p>
          <div className="max-h-96 overflow-y-auto">
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-(--color-surface) text-left text-sm text-(--steel)"><tr><th className="py-2">Row</th><th>Code</th><th>Action</th><th>Problem</th></tr></thead>
              <tbody>
                {preview.map((p) => (
                  <tr key={p.row_number} className="border-t border-(--border)">
                    <td className="py-1.5">{p.row_number + 1}</td><td className="id-code">{p.source_code}</td>
                    <td>{p.action}</td><td className="text-(--brick)">{p.error}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <button className="btn-primary mt-4 px-4 py-2 text-sm" disabled={pending || errors > 0} onClick={confirmImport}>
            {pending ? "Importing…" : `Confirm import of ${preview.length} rows`}
          </button>
          {errors > 0 && <p className="mt-2 text-xs text-(--brick)">Fix the rows with problems and upload the file again.</p>}
        </div>
      )}
    </div>
  );
}
