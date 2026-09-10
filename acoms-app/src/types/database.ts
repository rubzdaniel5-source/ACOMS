/**
 * PLACEHOLDER — this should be regenerated from your actual live schema.
 *
 * I can't generate this properly from my sandbox: it requires either the
 * Supabase CLI connected to your project (network access I don't have here)
 * or the Supabase Dashboard. Once your migrations are applied, run:
 *
 *   npx supabase gen types typescript --project-id lnmzlnwwfctcwgiegmkh > src/types/database.ts
 *
 * (requires `npx supabase login` first). Until then, this loose type keeps
 * the app compiling but gives up real column-level type safety on Supabase
 * queries — treat that as a known gap, not a resolved one.
 */
export type Database = {
  public: {
    Tables: Record<string, { Row: any; Insert: any; Update: any }>;
    Views: Record<string, { Row: any }>;
    Functions: Record<string, { Args: any; Returns: any }>;
  };
};
