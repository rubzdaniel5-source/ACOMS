import { chromium } from "playwright-core";
export const BASE = "http://localhost:3100";
let browser;
export async function session(user, width = 1280) {
  browser ??= await chromium.launch({ executablePath: "/opt/pw-browsers/chromium", args: ["--no-sandbox"] });
  const ctx = await browser.newContext({ viewport: { width, height: 900 } });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log("PAGEERROR", user, e.message));
  await page.goto(BASE + "/login");
  await page.fill('input[type="email"]', user + "@test.local");
  await page.fill('input[type="password"]', "pw");
  await page.click('button[type="submit"]');
  await page.waitForURL("**/dashboard", { timeout: 60000 });
  return page;
}
export const close = async () => browser?.close();
export async function open(p, path) {
  await p.goto(BASE + path);
  await p.waitForFunction(() => document.querySelector("h1") && !document.querySelector("[class*=skeleton],[aria-busy=true]"), null, { timeout: 90000 });
  await p.waitForTimeout(600);
}
export const text = async (p) => (await p.locator("body").innerText());
