import { test } from "node:test";
import assert from "node:assert/strict";
import { fetchAll } from "../src/lib/supabase/fetchAll.ts";

const rows = (n: number, start = 0) => Array.from({ length: n }, (_, i) => ({ id: start + i }));
const page = (data: { id: number }[] | null, error: { message: string } | null = null) => Promise.resolve({ data, error });

test("returns a single short page without asking for more", async () => {
  const calls: [number, number][] = [];
  const r = await fetchAll((from, to) => { calls.push([from, to]); return page(rows(10)); });
  assert.equal(r.error, null);
  assert.equal(r.data?.length, 10);
  assert.deepEqual(calls, [[0, 999]]);
});

test("keeps paging while pages are full, so nothing is cut off at 1,000 rows", async () => {
  const calls: [number, number][] = [];
  const r = await fetchAll((from, to) => {
    calls.push([from, to]);
    return page(from === 0 ? rows(1000) : from === 1000 ? rows(1000, 1000) : rows(250, 2000));
  });
  assert.equal(r.data?.length, 2250);
  assert.deepEqual(calls, [[0, 999], [1000, 1999], [2000, 2999]]);
  assert.equal(r.data?.[2249].id, 2249);
});

test("an exact multiple of the page size ends on the next empty page", async () => {
  let n = 0;
  const r = await fetchAll(() => page(n++ === 0 ? rows(1000) : []));
  assert.equal(r.data?.length, 1000);
  assert.equal(n, 2);
});

test("an error on any page returns the error and no partial data", async () => {
  const r = await fetchAll((from) => (from === 0 ? page(rows(1000)) : page(null, { message: "boom" })));
  assert.equal(r.data, null);
  assert.equal(r.error?.message, "boom");
});

test("null data with no error is treated as empty", async () => {
  const r = await fetchAll(() => page(null));
  assert.deepEqual(r.data, []);
});
