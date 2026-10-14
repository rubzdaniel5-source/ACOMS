import type { Metadata, Viewport } from "next";
import { IBM_Plex_Sans, IBM_Plex_Mono } from "next/font/google";
import "./globals.css";
import { createClient } from "@/lib/supabase/server";
import { NavBar } from "@/components/ui/NavBar";
import { getCurrentUserPermissions } from "@/features/auth/permissions";
import { canEnterAdmin } from "@/features/admin/access";
import { THEME_INIT_SCRIPT } from "@/features/theme/theme";
import { ThemeSync } from "@/features/theme/ThemeSync";
import { PwaClient } from "@/components/pwa/PwaClient";

const plexSans = IBM_Plex_Sans({
  variable: "--font-plex-sans",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
});

const plexMono = IBM_Plex_Mono({
  variable: "--font-plex-mono",
  subsets: ["latin"],
  weight: ["400", "500", "600"],
});

export const metadata: Metadata = {
  title: "ACOMS — Airline Catering Operations Management System",
  description: "Airline Catering Operations Management System",
  applicationName: "ACOMS",
  appleWebApp: { capable: true, title: "ACOMS", statusBarStyle: "default" },
  icons: { icon: "/icons/icon-192.png", apple: "/icons/apple-touch-icon.png" },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#2563EB" },
    { media: "(prefers-color-scheme: dark)", color: "#0F172A" },
  ],
};

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  let userName: string | null = null;
  let showAdmin = false;
  let accountTheme: string | null = null;
  if (user) {
    const { data: profile } = await supabase
      .from("user_profiles")
      .select("full_name")
      .eq("id", user.id)
      .single();
    userName = profile?.full_name ?? null;
    showAdmin = canEnterAdmin(await getCurrentUserPermissions());
    // Separate query: before migration 024 this column does not exist and must not hide the user name.
    const { data: themeRow } = await supabase.from("user_profiles").select("theme_preference").eq("id", user.id).single();
    accountTheme = (themeRow as { theme_preference?: string | null } | null)?.theme_preference ?? null;
  }

  return (
    <html lang="en" suppressHydrationWarning className={`h-full antialiased ${plexSans.variable} ${plexMono.variable}`}>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME_INIT_SCRIPT }} />
      </head>
      <body className="min-h-full flex flex-col font-sans bg-(--color-bg) text-(--color-text)">
        <PwaClient />
        {user && <ThemeSync accountTheme={accountTheme} />}
        {user && <NavBar userName={userName} showAdmin={showAdmin} />}
        {children}
      </body>
    </html>
  );
}
