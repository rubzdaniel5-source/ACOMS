"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { createExchangeAction } from "@/features/exchanges/actions";
import { MovementForm } from "@/features/exchanges/MovementForm";

type Station = { id: string; code: string; name: string; station_type: string };

export default function NewExchangePage() {
  const router = useRouter();
  const [stations, setStations] = useState<Station[] | null>(null);

  useEffect(() => {
    createClient().from("stations").select("id, code, name, station_type").eq("is_active", true).order("code")
      .then(({ data }) => setStations((data as Station[]) ?? []));
  }, []);

  const hub = stations?.find((s) => s.station_type === "HUB");
  const outstations = (stations ?? []).filter((s) => s.station_type === "STOCK_HOLDING");

  return (
    <div className="mx-auto w-full max-w-5xl px-3 py-6 sm:px-6">
      <Link href="/exchanges" className="mb-4 inline-block text-sm text-(--color-primary) hover:underline">Back to exchanges</Link>
      <h1 className="mb-1 text-2xl font-semibold text-(--color-text)">New Exchange</h1>
      <p className="mb-6 text-sm text-(--color-text-muted)">
        Starts the outbound movement from {hub?.code ?? "the hub"} to an outstation. Nothing moves until it is approved and dispatched.
        Stations that hold no stock are not listed: the hub loads their equipment for both sectors.
      </p>
      {!stations ? (
        <p className="text-sm text-(--steel)">Loading stations…</p>
      ) : !hub ? (
        <p className="alert alert-danger">No active hub station is configured.</p>
      ) : (
        <MovementForm
          mode="outbound"
          fromStationId={hub.id}
          fromCode={hub.code}
          destinations={outstations}
          submitLabel="Start exchange"
          onSubmit={async (v) => {
            const r = await createExchangeAction({
              outstationId: v.toStationId, items: v.items, reason: v.reason, priority: v.priority,
              flightNumber: v.flightNumber, flightDate: v.flightDate, requestKey: v.requestKey,
            });
            if (!r.success) return r.error;
            router.push(`/exchanges/${r.exchangeId}`);
            return null;
          }}
        />
      )}
    </div>
  );
}
