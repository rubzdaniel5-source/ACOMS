import { open, text } from "./lib.mjs";
export const shot = (p, n) => p.screenshot({ path: `/tmp/e2e/${n}.png`, fullPage: true });
export const tag = async (p) => (await p.locator(".tag").first().innerText());
export async function dlg(p, reason = "e2e reason for this action") { const d = p.locator("dialog[open]"); await d.waitFor(); const t = d.locator("textarea, input[type=text]"); if (await t.count()) await t.first().fill(reason); await d.locator("button.btn-primary, button.btn-danger").last().click(); await p.waitForTimeout(3000); }
export async function pickFlight(p, selIndex, dateStart = 1) {
  const sel = p.locator("select").nth(selIndex);
  for (let d = dateStart; d < 12; d++) {
    const dt = new Date(Date.now() + d * 864e5).toISOString().slice(0, 10);
    await p.fill('input[type="date"]', dt); await p.waitForTimeout(1500);
    if ((await sel.locator("option").count()) > 1) { await sel.selectOption({ index: 1 }); return [dt, await sel.locator("option:checked").innerText()]; }
  }
}
export async function opt(sel, re) { const v = await sel.locator("option").evaluateAll((os, r) => os.find(o => new RegExp(r).test(o.textContent))?.value, re); await sel.selectOption(v); }
