import { createClient } from "@/lib/supabase/server";
import { requireAnyPermission } from "@/features/admin/access";
import { SettingsForm } from "./SettingsForm";

export default async function SettingsPage() {
  await requireAnyPermission(["manage_configuration"]);
  const supabase = await createClient();
  const [settings, history] = await Promise.all([
    supabase.rpc("admin_list_settings"),
    supabase.from("audit_logs").select("id, created_at, action, actor_label, reason, before_state, after_state")
      .eq("entity_type", "setting").order("created_at", { ascending: false }).limit(15),
  ]);

  return (
    <div>
      <h1 className="mb-1 text-xl font-semibold text-(--navy)">System settings</h1>
      <p className="mb-6 text-sm text-(--steel)">
        The operating rules behind alerts and defaults. Changes apply immediately everywhere and are recorded in the audit trail.
        Most of these started as provisional values pending operational confirmation.
      </p>
      {settings.error && <p className="mb-4 text-sm text-(--brick)">{settings.error.message}</p>}
      <SettingsForm settings={(settings.data ?? []) as any} />

      <h2 className="mb-2 mt-8 text-base font-semibold text-(--steel)">Recent changes</h2>
      <div className="panel">
        {(history.data ?? []).length === 0 && <p className="p-4 text-sm text-(--steel)">No changes yet — everything is at its default.</p>}
        {((history.data ?? []) as any[]).map((h) => (
          <div key={h.id} className="flex flex-wrap justify-between gap-2 border-t border-(--border) p-3 text-sm first:border-t-0">
            <span>
              <span className="id-code">{h.after_state?.key}</span>{" "}
              {h.before_state?.value} → <strong>{h.after_state?.value}</strong>
              {h.reason ? <span className="text-(--steel)"> — {h.reason}</span> : null}
            </span>
            <span className="whitespace-nowrap text-(--steel)">{h.actor_label ?? "System"} · {new Date(h.created_at).toLocaleString("en-GB", { dateStyle: "short", timeStyle: "short" })}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
