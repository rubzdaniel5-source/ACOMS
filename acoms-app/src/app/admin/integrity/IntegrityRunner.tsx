"use client";

import Link from "next/link";
import { useState, useTransition } from "react";
import { runIntegrityCheck, type IntegrityDetail, type IntegritySummary } from "./actions";

export function IntegrityRunner() {
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<{ ranAt: string; summary: IntegritySummary[]; details: IntegrityDetail[] } | null>(null);

  function run() {
    setError(null);
    startTransition(async () => {
      const r = await runIntegrityCheck();
      if (!r.ok) return setError(r.error);
      setResult(r);
    });
  }

  const failed = result?.summary.filter((s) => s.failures > 0).length ?? 0;
  const label = Object.fromEntries((result?.summary ?? []).map((s) => [s.check_code, s.label]));

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-4">
        <button className="btn-primary px-5 py-2 text-sm" disabled={pending} onClick={run}>{pending ? "Checking…" : result ? "Run again" : "Run integrity check"}</button>
        {result && <span className="text-sm text-(--steel)">Last run {new Date(result.ranAt).toLocaleTimeString("en-GB")}</span>}
      </div>
      {error && <p className="rounded-sm px-3 py-2 text-sm text-(--brick)" style={{ background: "var(--brick-surface)" }}>{error}</p>}

      {result && (
        <>
          <p className="rounded-sm px-3 py-2 text-sm font-medium" style={failed === 0 ? { background: "var(--teal-surface)", color: "var(--teal)" } : { background: "var(--brick-surface)", color: "var(--brick)" }}>
            {failed === 0 ? "All checks passed. Every stock figure is explained by its records." : `${failed} of ${result.summary.length} checks found problems.`}
          </p>
          <div className="panel">
            {result.summary.map((s) => (
              <div key={s.check_code} className="flex items-start justify-between gap-4 border-t border-(--border) p-4 first:border-t-0">
                <div>
                  <div className="font-medium">{s.label}</div>
                  <p className="text-sm text-(--steel)">{s.description}</p>
                </div>
                <div className="text-right">
                  {s.failures === 0 ? <span className="tag tag-teal">Passed</span> : <span className="tag tag-brick">{s.failures} problem{s.failures === 1 ? "" : "s"}</span>}
                  <div className="mt-1 text-xs text-(--steel)">{s.examined} records examined</div>
                </div>
              </div>
            ))}
          </div>

          {result.details.length > 0 && (
            <div>
              <h2 className="mb-2 font-semibold text-(--navy)">Problems found</h2>
              <div className="panel overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="text-left text-xs text-(--steel)">
                    <tr><th className="p-3">Check</th><th className="p-3">Station</th><th className="p-3">Equipment</th><th className="p-3 text-right">Records say</th><th className="p-3 text-right">Balance shows</th><th className="p-3">Detail</th></tr>
                  </thead>
                  <tbody>
                    {result.details.map((d, i) => (
                      <tr key={i} className="border-t border-(--border)">
                        <td className="p-3">{label[d.check_code]}</td>
                        <td className="id-code p-3">{d.station_code}</td>
                        <td className="p-3">{d.equipment_name}<div className="id-code text-xs text-(--steel)">{d.source_code}</div></td>
                        <td className="p-3 text-right">{d.expected}</td>
                        <td className="p-3 text-right font-medium text-(--brick)">{d.actual}</td>
                        <td className="p-3 text-(--steel)">{d.detail}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <p className="mt-3 text-sm text-(--steel)">
                A mismatch means a balance has changed without a matching record. Find out why before correcting it; once you know,
                fix real stock differences with a <Link href="/admin/adjustments" className="text-(--navy) underline">stock adjustment</Link>.
                Unexplained mismatches should be treated as a system defect.
              </p>
            </div>
          )}
        </>
      )}
    </div>
  );
}
