// 테슬라 슈퍼차저 충전 이력 → records 자동 임포트 (신규 세션만, 중복 방지).
// 사용자별 토큰(id=uid) 사용, 임포트 기록은 owner_id=uid 로 저장(격리).
// POST { vehicleId?: "<records.vehicle_id uuid>" }  (없으면 본인 첫 차량)
const CLIENT_ID = Deno.env.get("TESLA_CLIENT_ID") ?? "";
const CLIENT_SECRET = Deno.env.get("TESLA_CLIENT_SECRET") ?? "";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const AUTH = "https://auth.tesla.com/oauth2/v3";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(b: unknown, s = 200) {
  return new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json", ...CORS } });
}
const SBH = { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` };

async function uidFrom(req: Request): Promise<string | null> {
  const auth = req.headers.get("Authorization");
  if (!auth) return null;
  const r = await fetch(`${SB_URL}/auth/v1/user`, { headers: { apikey: SB_KEY, Authorization: auth } });
  if (!r.ok) return null;
  const u = await r.json().catch(() => null);
  return u?.id ?? null;
}
async function loadToken(uid: string) {
  const r = await fetch(`${SB_URL}/rest/v1/tesla_tokens?id=eq.${uid}&select=*`, { headers: SBH });
  const rows = await r.json();
  return Array.isArray(rows) ? rows[0] : null;
}
async function saveToken(uid: string, fields: Record<string, unknown>) {
  await fetch(`${SB_URL}/rest/v1/tesla_tokens?id=eq.${uid}`, {
    method: "PATCH",
    headers: { ...SBH, "Content-Type": "application/json", Prefer: "return=minimal" },
    body: JSON.stringify({ ...fields, updated_at: new Date().toISOString() }),
  });
}
async function refresh(uid: string, refreshToken: string): Promise<string | null> {
  const body = new URLSearchParams({
    grant_type: "refresh_token", client_id: CLIENT_ID, client_secret: CLIENT_SECRET, refresh_token: refreshToken,
  });
  const r = await fetch(`${AUTH}/token`, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body });
  const d = await r.json();
  if (!d.access_token) return null;
  const expires = new Date(Date.now() + (d.expires_in ?? 28800) * 1000).toISOString();
  await saveToken(uid, { access_token: d.access_token, expires_at: expires, ...(d.refresh_token ? { refresh_token: d.refresh_token } : {}) });
  return d.access_token;
}

const num = (v: unknown) => (typeof v === "number" && isFinite(v) ? v : 0);

function summarize(s: Record<string, any>) {
  let kwh = 0, won = 0;
  const fees = Array.isArray(s.fees) ? s.fees : [];
  for (const f of fees) {
    won += num(f.totalDue);
    if (String(f.uom ?? "").toLowerCase() === "kwh") {
      kwh += num(f.usageBase) + num(f.usageTier1) + num(f.usageTier2) + num(f.usageTier3) + num(f.usageTier4);
    }
  }
  if (kwh === 0) kwh = num(s.energyUsed);
  let minutes = 0;
  const a = Date.parse(s.chargeStartDateTime), b = Date.parse(s.chargeStopDateTime);
  if (isFinite(a) && isFinite(b) && b > a) minutes = Math.round((b - a) / 60000);
  return { kwh, won: Math.round(won), minutes };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (!CLIENT_ID || !CLIENT_SECRET) return json({ error: "no_key" });

  const uid = await uidFrom(req);
  if (!uid) return json({ error: "no_session", message: "로그인 세션이 필요해요" }, 401);

  const body = await req.json().catch(() => ({}));
  const row = await loadToken(uid);
  if (!row || !row.access_token) return json({ error: "not_connected", message: "테슬라 미연결" });

  let access = row.access_token as string;
  const fleet = (row.fleet_base as string) || "https://fleet-api.prd.na.vn.cloud.tesla.com";

  if (row.expires_at && new Date(row.expires_at as string).getTime() < Date.now() + 60000) {
    const na = await refresh(uid, row.refresh_token as string);
    if (na) access = na; else return json({ error: "reauth", message: "재로그인 필요" });
  }
  const H = { Authorization: `Bearer ${access}` };

  let vin = (row.vin as string) || "";
  if (!vin) {
    try {
      const vr = await fetch(`${fleet}/api/1/vehicles`, { headers: H });
      const vd = await vr.json();
      vin = String(vd?.response?.[0]?.vin ?? "");
      if (vin) await saveToken(uid, { vin });
    } catch (_) { /* ignore */ }
  }
  if (!vin) return json({ error: "no_vin", message: "VIN을 확인할 수 없어요" });

  // 대상 차량(records.vehicle_id) — 미지정 시 본인 첫 차량
  let vehicleId = String(body.vehicleId ?? "");
  if (!vehicleId) {
    const vr = await fetch(`${SB_URL}/rest/v1/vehicles?owner_id=eq.${uid}&select=id&order=created_at.asc&limit=1`, { headers: SBH });
    vehicleId = (await vr.json())?.[0]?.id ?? "";
  }
  if (!vehicleId) return json({ error: "no_target", message: "대상 차량 없음" });

  // 모든 페이지 순회 → 연결 이전 과거 이력까지 전부 (안전 상한 2000건)
  const PAGE = 50, MAX_PAGES = 40;
  const sessions: Record<string, any>[] = [];
  let firstBodySample = "";
  for (let page = 1; page <= MAX_PAGES; page++) {
    const histURL =
      `${fleet}/api/1/dx/charging/history?vin=${encodeURIComponent(vin)}` +
      `&pageNo=${page}&pageSize=${PAGE}&sortBy=start_datetime&sortOrder=DESC`;
    const cr = await fetch(histURL, { headers: H });
    const raw = await cr.text();
    if (page === 1) {
      firstBodySample = raw.slice(0, 300);
      console.log(`[charging] page1 status=${cr.status} len=${raw.length} vin=${vin} body=${firstBodySample}`);
    }
    if (!cr.ok) {
      if (page === 1) {
        return json({ error: cr.status === 403 ? "scope" : "history_failed", status: cr.status, message: raw.slice(0, 240) });
      }
      break; // 이후 페이지 실패 → 여기까지 수집분만 사용
    }
    let cd: any = {};
    try { cd = JSON.parse(raw); } catch (_) { /* ignore */ }
    const batch: Record<string, any>[] = cd?.response?.data ?? cd?.response?.results ??
      (Array.isArray(cd?.response) ? cd.response : []) ?? [];
    if (page === 1) console.log(`[charging] page1 parsed count=${Array.isArray(batch) ? batch.length : "n/a"} keys=${Object.keys(cd?.response ?? {}).join(",")}`);
    if (!Array.isArray(batch) || batch.length === 0) break;
    sessions.push(...batch);
    if (batch.length < PAGE) break; // 마지막 페이지
  }
  if (sessions.length === 0) return json({ imported: 0, total: 0, debug: firstBodySample });

  const er = await fetch(
    `${SB_URL}/rest/v1/records?vehicle_id=eq.${vehicleId}&ext_id=like.tesla-charge-*&select=ext_id`,
    { headers: SBH },
  );
  const existing = new Set(((await er.json()) as any[]).map((r) => r.ext_id));

  const rows: Record<string, unknown>[] = [];
  for (const s of sessions) {
    const sid = String(s.sessionId ?? s.session_id ?? "");
    if (!sid) continue;
    const ext = `tesla-charge-${sid}`;
    if (existing.has(ext)) continue;
    const { kwh, won, minutes } = summarize(s);
    const kwhLabel = kwh > 0 ? `${Math.round(kwh * 10) / 10}kWh` : "";
    rows.push({
      owner_id: uid,
      vehicle_id: vehicleId,
      kind: "charge",
      title: kwhLabel ? `슈퍼차저 · ${kwhLabel}` : "슈퍼차저 충전",
      occurred_at: s.chargeStartDateTime ?? new Date().toISOString(),
      amount_won: won > 0 ? won : null,
      distance_km: null,
      duration_min: minutes > 0 ? minutes : null,
      location: s.siteLocationName ?? null,
      tag: "Tesla",
      ai_logged: true,
      ext_id: ext,
    });
  }

  if (rows.length === 0) return json({ imported: 0, total: sessions.length });

  const ir = await fetch(`${SB_URL}/rest/v1/records`, {
    method: "POST",
    headers: { ...SBH, "Content-Type": "application/json", Prefer: "return=minimal,resolution=ignore-duplicates" },
    body: JSON.stringify(rows),
  });
  if (!ir.ok) {
    const t = await ir.text();
    return json({ error: "insert_failed", status: ir.status, message: t.slice(0, 240) });
  }
  return json({ imported: rows.length, total: sessions.length });
});
