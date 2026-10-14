"use client";

import { useEffect, useState, useSyncExternalStore } from "react";

const subscribe = (cb: () => void) => {
  window.addEventListener("online", cb);
  window.addEventListener("offline", cb);
  return () => { window.removeEventListener("online", cb); window.removeEventListener("offline", cb); };
};

// Registers the service worker and warns when the connection drops.
export function PwaClient() {
  const online = useSyncExternalStore(subscribe, () => navigator.onLine, () => true);
  const [justRestored, setJustRestored] = useState(false);
  const [wasOffline, setWasOffline] = useState(false);

  useEffect(() => {
    if ("serviceWorker" in navigator && process.env.NODE_ENV === "production") {
      navigator.serviceWorker.register("/sw.js", { scope: "/", updateViaCache: "none" }).catch(() => {});
    }
  }, []);

  useEffect(() => {
    if (!online) { setWasOffline(true); return; }
    if (wasOffline) {
      setJustRestored(true);
      const t = setTimeout(() => setJustRestored(false), 4000);
      return () => clearTimeout(t);
    }
  }, [online, wasOffline]);

  if (online && !justRestored) return null;
  return (
    <div role="status" aria-live="polite" className={`alert ${online ? "alert-success" : "alert-warning"} rounded-none text-center`}>
      {online
        ? "Back online."
        : "You are offline. What is on screen may be out of date, and changes cannot be saved until you reconnect."}
    </div>
  );
}
