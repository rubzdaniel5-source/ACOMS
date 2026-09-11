import type { Metadata } from "next";
import "./globals.css";
import { createClient } from "@/lib/supabase/server";
import { NavBar } from "@/components/ui/NavBar";

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
    <html lang="en" className="h-full antialiased">
      <body className="min-h-full flex flex-col font-sans bg-slate-50">
        {user && <NavBar />}
        {children}
      </body>
    </html>
  );
}
