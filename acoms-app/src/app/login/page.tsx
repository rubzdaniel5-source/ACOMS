"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const router = useRouter();

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);

    const supabase = createClient();
    const { error } = await supabase.auth.signInWithPassword({ email, password });

    setLoading(false);
    if (error) {
      setError(error.message);
      return;
    }
    router.push("/dashboard");
    router.refresh();
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-(--color-surface-subtle) px-4">
      <div className="w-full max-w-sm rounded-lg border border-(--color-border) bg-(--color-surface) p-8 shadow-sm">
        <h1 className="mb-1 text-xl font-semibold text-(--color-text)">ACOMS</h1>
        <p className="mb-6 text-sm text-(--color-text-subtle)">Sign in to continue</p>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="mb-1 block text-sm font-medium text-(--color-text-muted)">Email</label>
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full rounded-md border border-(--color-border-strong) px-3 py-2 text-sm focus:border-(--color-primary) focus:outline-none"
            />
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-(--color-text-muted)">Password</label>
            <input
              type="password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full rounded-md border border-(--color-border-strong) px-3 py-2 text-sm focus:border-(--color-primary) focus:outline-none"
            />
          </div>

          {error && (
            <p className="rounded-md bg-(--color-danger-soft) px-3 py-2 text-sm text-(--color-danger)">{error}</p>
          )}

          <button
            type="submit"
            disabled={loading}
            className="w-full rounded-md bg-(--color-action) px-4 py-2 text-sm font-medium text-(--color-on-action) hover:bg-(--color-action-hover) disabled:opacity-50"
          >
            {loading ? "Signing in..." : "Sign in"}
          </button>
        </form>
      </div>
    </div>
  );
}
