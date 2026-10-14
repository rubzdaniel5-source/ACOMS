"use client";

import { useEffect, useState } from "react";
import { applyTheme, DEFAULT_THEME, readLocalTheme, THEME_EVENT, writeLocalTheme, type ThemePreference } from "./theme";
import { saveThemePreference } from "./actions";

const OPTIONS: { value: ThemePreference; label: string; hint: string }[] = [
  { value: "light", label: "Light", hint: "Aero Blue, always" },
  { value: "dark", label: "Dark", hint: "Slate Modern, always" },
  { value: "system", label: "System", hint: "Follow this device" },
];

export function ThemeSelector() {
  const [pref, setPref] = useState<ThemePreference>(DEFAULT_THEME);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    // localStorage is only readable on the client; reading after mount avoids a hydration mismatch.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setPref(readLocalTheme() ?? DEFAULT_THEME);
    setReady(true);
    const onSync = () => setPref(readLocalTheme() ?? DEFAULT_THEME);
    window.addEventListener(THEME_EVENT, onSync);
    return () => window.removeEventListener(THEME_EVENT, onSync);
  }, []);

  // Keep System mode in step with the device while it is selected.
  useEffect(() => {
    if (pref !== "system") return;
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const apply = () => applyTheme("system");
    mq.addEventListener("change", apply);
    return () => mq.removeEventListener("change", apply);
  }, [pref]);

  function choose(next: ThemePreference) {
    setPref(next);
    writeLocalTheme(next);
    applyTheme(next);
    void saveThemePreference(next);
  }

  return (
    <fieldset className="panel p-5" disabled={!ready}>
      <legend className="sr-only">Theme</legend>
      <div className="grid gap-3 sm:grid-cols-3">
        {OPTIONS.map((o) => (
          <label
            key={o.value}
            className={`flex min-h-11 cursor-pointer items-start gap-3 rounded-lg border p-3 ${
              pref === o.value
                ? "border-(--color-primary) bg-(--color-primary-soft)"
                : "border-(--color-border) hover:bg-(--color-surface-hover)"
            }`}
          >
            <input
              type="radio"
              name="theme"
              value={o.value}
              checked={pref === o.value}
              onChange={() => choose(o.value)}
              className="mt-1"
            />
            <span>
              <span className="block text-sm font-semibold text-(--color-text)">{o.label}</span>
              <span className="block text-xs text-(--color-text-subtle)">{o.hint}</span>
            </span>
          </label>
        ))}
      </div>
      <p className="mt-3 text-xs text-(--color-text-subtle)" role="status">
        Saved to your account and this device. Changing the theme does not affect your work or data.
      </p>
    </fieldset>
  );
}
