import { createClient } from "@/lib/supabase/server";
import { requireAnyPermission } from "@/features/admin/access";
import { FlightManager, type Route, type Leg, type Station } from "./FlightManager";

export default async function FlightsPage() {
  const perms = await requireAnyPermission(["manage_flights"]);
  const supabase = await createClient();
  const today = new Date().toISOString().slice(0, 10);
  const [routes, legs, stations] = await Promise.all([
    supabase.from("v_flight_routes")
      .select("id, flight_number, origin_code, destination_code, operating_days, valid_from, valid_to, is_active, source")
      .order("flight_number").limit(500),
    supabase.from("v_flight_legs")
      .select("id, flight_number, operating_date, origin_code, destination_code, status, is_one_off, cancel_reason, is_unverified")
      .gte("operating_date", today).order("operating_date").limit(200),
    supabase.from("stations").select("id, code, name").eq("is_active", true).order("code"),
  ]);
  return (
    <div>
      <h1 className="mb-1 text-xl font-semibold text-(--navy)">Flights</h1>
      <p className="mb-6 text-sm text-(--steel)">
        The flight schedule used to link equipment movements to a real flight. Each sector is its own entry. Flight numbers continue across
        seasons, so a scheduled flight runs every week until it is deactivated. Base staff can enter a flight that is not listed; it shows here as unverified until you confirm it.
      </p>
      <FlightManager
        routes={(routes.data ?? []) as Route[]}
        legs={(legs.data ?? []) as Leg[]}
        stations={(stations.data ?? []) as Station[]}
        canManage={perms.has("manage_flights")}
        today={today}
      />
    </div>
  );
}
