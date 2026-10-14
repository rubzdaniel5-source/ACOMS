// Theme preference: "light" (Aero Blue), "dark" (Slate Modern) or "system".
// Storage strategy (ACOMS-DESIGN-001 4.1): the preference alone is kept in
// localStorage under THEME_KEY; nothing else. Precedence: saved preference,
// then default "light". "system" follows prefers-color-scheme and updates live.
export type ThemePreference = "light" | "dark" | "system";
export const THEME_KEY = "acoms-theme";
export const DEFAULT_THEME: ThemePreference = "light";

// Runs inline in <head> before first paint so the wrong theme never flashes.
export const THEME_INIT_SCRIPT = `(function(){try{var p=localStorage.getItem("${THEME_KEY}");if(p!=="light"&&p!=="dark"&&p!=="system")p="${DEFAULT_THEME}";var d=p==="dark"||(p==="system"&&window.matchMedia("(prefers-color-scheme: dark)").matches);document.documentElement.setAttribute("data-theme",d?"dark":"light");}catch(e){document.documentElement.setAttribute("data-theme","light");}})();`;

export const THEME_EVENT = "acoms-theme-change";

export function isThemePreference(v: unknown): v is ThemePreference {
  return v === "light" || v === "dark" || v === "system";
}

export function readLocalTheme(): ThemePreference | null {
  try {
    const v = localStorage.getItem(THEME_KEY);
    return isThemePreference(v) ? v : null;
  } catch {
    return null;
  }
}

export function writeLocalTheme(pref: ThemePreference) {
  try {
    localStorage.setItem(THEME_KEY, pref);
  } catch {}
}

export function applyTheme(pref: ThemePreference) {
  const dark = pref === "dark" || (pref === "system" && window.matchMedia("(prefers-color-scheme: dark)").matches);
  document.documentElement.setAttribute("data-theme", dark ? "dark" : "light");
}
