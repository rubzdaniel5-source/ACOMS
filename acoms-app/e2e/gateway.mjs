// Stand-in for Supabase: /auth/v1 (password login, user, logout) and /rest/v1 -> PostgREST.
import http from "node:http";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";
const SECRET = "e2e-secret-e2e-secret-e2e-secret-123456";
const b64 = (b) => Buffer.from(b).toString("base64url");
const sign = (p) => { const h = b64(JSON.stringify({ alg: "HS256", typ: "JWT" })), pl = b64(JSON.stringify(p));
  return `${h}.${pl}.${crypto.createHmac("sha256", SECRET).update(`${h}.${pl}`).digest("base64url")}`; };
const verify = (t) => { try { const [h, p, s] = t.split("."); const e = crypto.createHmac("sha256", SECRET).update(`${h}.${p}`).digest("base64url");
  if (e !== s) return null; const c = JSON.parse(Buffer.from(p, "base64url")); return c.exp && c.exp < Date.now() / 1000 ? null : c; } catch { return null; } };
const psql = (q) => execFileSync("psql", ["-d", "acoms_e2e", "-At", "-c", q], { encoding: "utf8" }).trim();
export const anonKey = sign({ role: "anon", iss: "e2e", exp: 4102444800 });
const userObj = (id, email) => ({ id, aud: "authenticated", role: "authenticated", email, app_metadata: {}, user_metadata: {}, created_at: new Date().toISOString() });
http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://x");
  const chunks = []; for await (const c of req) chunks.push(c); const body = Buffer.concat(chunks);
  const json = (code, o) => { res.writeHead(code, { "content-type": "application/json", "access-control-allow-origin": req.headers.origin || "*", "access-control-allow-credentials": "true", "access-control-allow-headers": "*", "access-control-allow-methods": "*" }); res.end(JSON.stringify(o)); };
  if (req.method === "OPTIONS") return json(200, {});
  if (url.pathname === "/auth/v1/token") {
    const { email, password } = JSON.parse(body.toString() || "{}");
    const row = password === "pw" ? psql(`select id from auth.users where email='${String(email).replace(/'/g, "")}'`) : "";
    if (!row) return json(400, { error: "invalid_grant", error_description: "Invalid login credentials" });
    const now = Math.floor(Date.now() / 1000);
    const access = sign({ sub: row, email, role: "authenticated", aud: "authenticated", iat: now, exp: now + 36000 });
    return json(200, { access_token: access, token_type: "bearer", expires_in: 36000, expires_at: now + 36000, refresh_token: "r-" + row, user: userObj(row, email) });
  }
  if (url.pathname === "/auth/v1/user") {
    const c = verify((req.headers.authorization || "").replace(/^Bearer /, ""));
    return c && c.sub ? json(200, userObj(c.sub, c.email)) : json(401, { msg: "invalid JWT" });
  }
  if (url.pathname === "/auth/v1/logout") return json(204, {});
  if (url.pathname.startsWith("/rest/v1/")) {
    const headers = { ...req.headers }; delete headers.host; delete headers["content-length"];
    const r = await fetch("http://127.0.0.1:3001" + url.pathname.replace("/rest/v1", "") + url.search, { method: req.method, headers, body: ["GET", "HEAD"].includes(req.method) ? undefined : body });
    const out = Buffer.from(await r.arrayBuffer()); const h = Object.fromEntries(r.headers); delete h["content-encoding"]; delete h["transfer-encoding"]; delete h["content-length"];
    h["access-control-allow-origin"] = req.headers.origin || "*"; h["access-control-allow-credentials"] = "true"; h["access-control-expose-headers"] = "*";
    res.writeHead(r.status, h); return res.end(out);
  }
  json(404, { msg: "not found" });
}).listen(54321, () => console.log("gateway on 54321\nANON=" + anonKey));
