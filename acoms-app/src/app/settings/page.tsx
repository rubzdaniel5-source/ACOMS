import { ThemeSelector } from "@/features/theme/ThemeSelector";

export default function SettingsPage() {
  return (
    <div className="mx-auto w-full max-w-3xl px-4 py-6 sm:px-6">
      <h1 className="text-2xl font-semibold text-(--color-text)">Settings</h1>
      <h2 className="mb-3 mt-6 text-base font-semibold text-(--color-text)">Appearance</h2>
      <ThemeSelector />
    </div>
  );
}
