import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { requireAnyPermission } from "@/features/admin/access";
import { getCurrentUserId } from "@/features/auth/permissions";
import { AdjustmentsTable } from "./AdjustmentsTable";

export default async function AdjustmentsPage() {
  const perms = await requireAnyPermission(["request_adjustment", "approve_adjustment"]);
  const me = await getCurrentUserId();
  const supabase = await createClient();
  const { data } = await supabase.from("v_stock_adjustments").select("*").order("requested_at", { ascending: false }).limit(300);

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="mb-1 text-xl font-semibold text-(--navy)">Stock adjustments</h1>
          <p className="text-sm text-(--steel)">Corrections to recorded stock. One person requests, a different person approves; the ledger changes only on approval.</p>
        </div>
        {perms.has("request_adjustment") && <Link href="/admin/adjustments/new" className="btn-primary px-4 py-2 text-sm">New adjustment</Link>}
      </div>
      <AdjustmentsTable rows={(data ?? []) as any} me={me} canApprove={perms.has("approve_adjustment")} />
    </div>
  );
}
