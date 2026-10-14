// Supabase returns at most 1,000 rows per request. Anything that must see every
// row (counts, health totals, exports) reads in pages so growth can never
// silently truncate it. The builder must apply a stable, unique-enough order.
const PAGE = 1000;

type Page<T> = PromiseLike<{ data: T[] | null; error: { message: string } | null }>;

export async function fetchAll<T>(build: (from: number, to: number) => Page<T>): Promise<{ data: T[] | null; error: { message: string } | null }> {
  const rows: T[] = [];
  for (let from = 0; ; from += PAGE) {
    const { data, error } = await build(from, from + PAGE - 1);
    if (error) return { data: null, error };
    rows.push(...(data ?? []));
    if (!data || data.length < PAGE) break;
  }
  return { data: rows, error: null };
}
