import { createClient } from "@/lib/supabase/server";
import { requireAnyPermission } from "@/features/admin/access";
import { StationManager } from "./StationManager";

export default async function StationsPage() {
  const perms = await requireAnyPermission(["manage_configuration"]);
  const supabase = await createClient();
  const { data } = await supabase
    .from("stations")
    .select("id, code, name, station_type, airport_code, country, timezone, is_active")
    .order("code");
  return (
    <div>
      <h1 className="mb-1 text-xl font-semibold text-(--navy)">Stations</h1>
      <p className="mb-6 text-sm text-(--steel)">
        Stock-holding stations keep their own equipment. No-stock turnaround stations never hold equipment; the hub loads everything for both sectors.
      </p>
      <StationManager stations={(data ?? []) as any} canEdit={perms.has("manage_configuration")} />
    </div>
  );
}
