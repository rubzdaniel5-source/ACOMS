"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { resetSetting, saveSetting } from "./actions";

type Setting = {
  key: string; category: string; label: string; description: string; unit: string; default_value: number;
  min_value: number; max_value: number; step: number; value: number; is_overridden: boolean;
  updated_at: string | null; updated_by_name: string | null;
};

export function SettingsForm({ settings }: { settings: Setting[] }) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [draft, setDraft] = useState<Record<string, string>>({});
  const [reasons, setReasons] = useState<Record<string, string>>({});
  const [msg, setMsg] = useState<{ key: string; ok: boolean; text: string } | null>(null);

  const value = (s: Setting) => Number(draft[s.key] ?? s.value);
  const byKey = Object.fromEntries(settings.map((s) => [s.key, s]));
  const groups = Array.from(new Set(settings.map((s) => s.category)));

  function run(key: string, fn: () => Promise<{ ok: boolean; error?: string }>, okText: string) {
    setMsg(null);
    startTransition(async () => {
      const r = await fn();
      if (!r.ok) return setMsg({ key, ok: false, text: r.error ?? "Failed" });
      setDraft((d) => { const n = { ...d }; delete n[key]; return n; });
      setReasons((d) => { const n = { ...d }; delete n[key]; return n; });
      setMsg({ key, ok: true, text: okText });
      router.refresh();
    });
  }

  const ex = 100;
  const h = (k: string) => value(byKey[k] ?? ({ value: 0, key: k } as Setting));

  return (
    <div className="space-y-6">
      {groups.map((g) => (
        <section key={g} className="panel p-4">
          <h2 className="mb-3 font-semibold text-(--navy)">{g}</h2>

          {g === "Stock health" && byKey["health.surplus_ratio"] && (
            <p className="mb-4 rounded-sm px-3 py-2 text-sm" style={{ background: "var(--steel-light)" }}>
              Example with a reorder threshold of {ex}: critical shortage below <strong>{ex * h("health.critical_shortage_ratio")}</strong>,
              shortage below <strong>{ex * h("health.shortage_ratio")}</strong>, normal up to <strong>{ex * h("health.surplus_ratio")}</strong>,
              surplus up to <strong>{ex * h("health.critical_surplus_ratio")}</strong>, critical surplus above that.
            </p>
          )}

          <div className="divide-y divide-(--border)">
            {settings.filter((s) => s.category === g).map((s) => {
              const dirty = draft[s.key] !== undefined && Number(draft[s.key]) !== s.value;
              return (
                <div key={s.key} className="py-3">
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div className="min-w-60 flex-1">
                      <div className="flex items-center gap-2">
                        <span className="font-medium">{s.label}</span>
                        {s.is_overridden && <span className="tag tag-amber">Changed</span>}
                      </div>
                      <p className="text-sm text-(--steel)">{s.description}</p>
                      <p className="text-xs text-(--steel)">Default {s.default_value} · allowed {s.min_value}–{s.max_value}</p>
                    </div>
                    <div className="flex items-center gap-2">
                      <input type="number" step={s.step} min={s.min_value} max={s.max_value}
                        value={draft[s.key] ?? String(s.value)} onChange={(e) => setDraft({ ...draft, [s.key]: e.target.value })}
                        className="w-24 rounded-sm border border-(--border) px-2 py-1.5 text-right text-sm" />
                      <span className="w-28 text-xs text-(--steel)">{s.unit}</span>
                    </div>
                  </div>
                  {(dirty || s.is_overridden) && (
                    <div className="mt-2 flex flex-wrap items-center gap-2">
                      {dirty && (
                        <>
                          <input value={reasons[s.key] ?? ""} onChange={(e) => setReasons({ ...reasons, [s.key]: e.target.value })}
                            placeholder="Why? (optional, kept in the audit trail)" className="min-w-60 flex-1 rounded-sm border border-(--border) px-2 py-1.5 text-sm" />
                          <button className="btn-primary px-3 py-1.5 text-sm" disabled={pending}
                            onClick={() => run(s.key, () => saveSetting(s.key, Number(draft[s.key]), reasons[s.key] ?? ""), "Saved")}>Save</button>
                          <button className="btn-secondary px-3 py-1.5 text-sm" onClick={() => setDraft((d) => { const n = { ...d }; delete n[s.key]; return n; })}>Undo</button>
                        </>
                      )}
                      {s.is_overridden && !dirty && (
                        <button className="btn-secondary px-3 py-1.5 text-sm" disabled={pending} onClick={() => run(s.key, () => resetSetting(s.key), "Reset to default")}>Reset to default</button>
                      )}
                      {s.is_overridden && s.updated_by_name && !dirty && (
                        <span className="text-xs text-(--steel)">Last set by {s.updated_by_name}{s.updated_at ? `, ${new Date(s.updated_at).toLocaleDateString("en-GB", { dateStyle: "medium" })}` : ""}</span>
                      )}
                    </div>
                  )}
                  {msg?.key === s.key && <p className={`mt-2 text-sm ${msg.ok ? "text-(--teal)" : "text-(--brick)"}`}>{msg.text}</p>}
                </div>
              );
            })}
          </div>
        </section>
      ))}
    </div>
  );
}
