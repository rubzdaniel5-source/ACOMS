"use client";

import { useEffect } from "react";
import { applyTheme, isThemePreference, readLocalTheme, THEME_EVENT, writeLocalTheme } from "./theme";
import { saveThemePreference } from "./actions";

// Reconciles the saved account preference with this device. Precedence: the
// account preference wins when set (it follows the user across devices); if the
// account has none yet, this device's choice is saved to the account.
export function ThemeSync({ accountTheme }: { accountTheme: string | null }) {
  useEffect(() => {
    const local = readLocalTheme();
    if (isThemePreference(accountTheme)) {
      if (accountTheme !== local) {
        writeLocalTheme(accountTheme);
        applyTheme(accountTheme);
        window.dispatchEvent(new Event(THEME_EVENT));
      }
    } else if (local) {
      void saveThemePreference(local);
    }
  }, [accountTheme]);
  return null;
}
