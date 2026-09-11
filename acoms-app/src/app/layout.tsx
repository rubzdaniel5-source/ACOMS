import type { Metadata } from "next";
import { IBM_Plex_Sans, IBM_Plex_Mono } from "next/font/google";
import "./globals.css";
import { createClient } from "@/lib/supabase/server";
import { NavBar } from "@/components/ui/NavBar";

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
  title: "ACOMS",
  description: "Airline Catering Operations Management System",
};

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <html lang="en" className={`h-full antialiased ${plexSans.variable} ${plexMono.variable}`}>
      <body className="min-h-full flex flex-col font-sans bg-(--background) text-(--foreground)">
        {user && <NavBar />}
        {children}
      </body>
    </html>
  );
}
