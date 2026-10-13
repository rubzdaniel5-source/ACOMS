"use client";

import { useState, useTransition } from "react";
import { changePassword } from "./actions";

export default function ChangePasswordPage() {
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    if (password !== confirm) {
      setError("The two passwords do not match.");
      return;
    }
    startTransition(async () => {
      const res = await changePassword(password);
      if (res?.error) setError(res.error);
    });
  }

  return (
    <div className="mx-auto w-full max-w-sm px-4 py-12">
      <div className="panel p-8">
        <h1 className="mb-1 text-lg font-semibold text-(--navy)">Set a new password</h1>
        <p className="mb-6 text-sm text-(--steel)">
          Choose a personal password before continuing. Use at least 10 characters.
        </p>
        <form onSubmit={submit} className="space-y-4">
          <div>
            <label className="mb-1 block text-sm font-medium">New password</label>
            <input type="password" required minLength={10} autoComplete="new-password" value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full rounded-sm border border-(--border) px-3 py-2 text-sm" />
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium">Confirm password</label>
            <input type="password" required minLength={10} autoComplete="new-password" value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
              className="w-full rounded-sm border border-(--border) px-3 py-2 text-sm" />
          </div>
          {error && (
            <p className="rounded-sm px-3 py-2 text-sm text-(--brick)" style={{ background: "var(--brick-surface)" }}>{error}</p>
          )}
          <button type="submit" disabled={pending} className="btn-primary w-full px-4 py-2 text-sm">
            {pending ? "Saving…" : "Save password"}
          </button>
        </form>
      </div>
    </div>
  );
}
