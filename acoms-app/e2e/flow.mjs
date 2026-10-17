import { session, close, open, text } from "./lib.mjs";
import { shot, tag, dlg } from "./lib2.mjs";
export const tid = (n) => import("node:child_process").then(c => c.execSync(`su postgres -c "psql -d acoms_e2e -At -c \\"select id from equipment_transfers where transfer_number='${n}'\\""`).toString().trim());
export async function step(user, T, btn, fill) {
  const p = await session(user); await open(p, T);
  if (fill) await fill(p);
  await p.click(`button:has-text("${btn}")`); await p.waitForTimeout(800);
  if (await p.locator("dialog[open]").count()) await dlg(p);
  await p.waitForTimeout(2500); await open(p, T);
  const s = await tag(p); await p.context().close(); return s;
}
export const receive = (vals) => async (p) => { const n = p.locator("input[type=number]"); for (let i = 0; i < vals.length; i++) await n.nth(i).fill(String(vals[i])); };
