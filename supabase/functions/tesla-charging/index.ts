// 테슬라 슈퍼차저 충전 이력 → records 자동 임포트 (신규 세션만, 중복 방지).
// POST { vehicleId?: "<records.vehicle_id uuid>" }  (없으면 첫 차량)
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

async function loadToken() {
  const r = await fetch(`${SB_URL}/rest/v1/tesla_tokens?id=eq.default&select=*`, { headers: SBH });
  const rows = await r.json();
  return Array.isArray(rows) ? rows[0] : null;
}
async function saveToken(fields: Record<string, unknown>) {
  await fetch(`${SB_URL}/rest/v1/tesla_tokens?id=eq.default`, {
    method: "PATCH",
    headers: { ...SBH, "Content-Type": "application/json", Prefer: "return=minimal" },
    body: JSON.stringify({ ...fields, updated_at: new Date().toISOString() }),
  });
}
async function refresh(refreshToken: string): Promise<string | null> {
  const body = new URLSearchParams({
    grant_type: "refresh_token", client_id: CLIENT_ID, client_secret: CLIENT_SECRET, refresh_token: refreshToken,
  });
  const r = await fetch(`${AUTH}/token`, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body });
  const d = await r.json();
  if (!d.access_token) return null;
  const expires = new Date(Date.now() + (d.expires_in ?? 28800) * 1000).toISOString();
  await saveToken({ access_token: d.access_token, expires_at: expires, ...(d.refresh_token ? { refresh_token: d.refresh_token } : {}) });
  return d.access_token;
}

const num = (v: unknown) => (typeof v === "number" && isFinite(v) ? v : 0);

// 세션 1건 → { kwh, won, minutes }
function summarize(s: Record<string, any>) {
  let kwh = 0, won = 0;
  const fees = Array.isArray(s.fees) ? s.fees : [];
  for (const f of fees) {
    won += num(f.totalDue);
    if (String(f.uom ?? "").toLowerCase() === "kwh") {
      kwh += num(f.usageBase) + num(f.usageTier1) + num(f.usageTier2) + num(f.usageTier3) + num(f.usageTier4);
    }
  }
  if (kwh === 0) kwh = num(s.energyUsed);   // 폴백
  let minutes = 0;
  const a = Date.parse(s.chargeStartDateTime), b = Date.parse(s.chargeStopDateTime);
  if (isFinite(a) && isFinite(b) && b > a) minutes = Math.round((b - a) / 60000);
  return { kwh, won: Math.round(won), minutes };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (!CLIENT_ID || !CLIENT_SECRET) return json({ error: "no_key" });

  const body = await req.json().catch(() => ({}));
  const row = await loadToken();
  if (!row || !row.access_token) return json({ error: "not_connected", message: "테슬라 미연결" });

  let access = row.access_token as string;
  const fleet = (row.fleet_base as string) || "https://fleet-api.prd.na.vn.cloud.tesla.com";

  if (row.expires_at && new Date(row.expires_at as string).getTime() < Date.now() + 60000) {
    const na = await refresh(row.refresh_token as string);
    if (na) access = na; else return json({ error: "reauth", message: "재로그인 필요" });
  }
  const H = { Authorization: `Bearer ${access}` };

  // VIN 확보 (없으면 차량 목록에서 조회 후 저장)
  let vin = (row.vin as string) || "";
  if (!vin) {
    try {
      const vr = await fetch(`${fleet}/api/1/vehicles`, { headers: H });
      const vd = await vr.json();
      vin = String(vd?.response?.[0]?.vin ?? "");
      if (vin) await saveToken({ vin });
    } catch (_) { /* ignore */ }
  }
  if (!vin) return json({ error: "no_vin", message: "VIN을 확인할 수 없어요" });

  // 대상 차량(records.vehicle_id) — 미지정 시 첫 차량
  let vehicleId = String(body.vehicleId ?? "");
  if (!vehicleId) {
    const vr = await fetch(`${SB_URL}/rest/v1/vehicles?select=id&order=created_at.asc&limit=1`, { headers: SBH });
    vehicleId = (await vr.json())?.[0]?.id ?? "";
  }
  if (!vehicleId) return json({ error: "no_target", message: "대상 차량 없음" });

  // 충전 이력 조회
  const histURL = `${fleet}/api/1/dx/charging/history?vin=${encodeURIComponent(vin)}&pageSize=50&sortBy=start_datetime&sortOrder=DESC`;
  const cr = await fetch(histURL, { headers: H });
  if (!cr.ok) {
    const t = await cr.text();
    // 403 → 스코프 부족(vehicle_charging_cmds) 가능성
    return json({ error: cr.status === 403 ? "scope" : "history_failed", status: cr.status, message: t.slice(0, 240) });
  }
  const cd = await cr.json();
  const sessions: Record<string, any>[] = cd?.response?.data ?? cd?.response?.results ?? cd?.response ?? [];
  if (!Array.isArray(sessions) || sessions.length === 0) return json({ imported: 0, total: 0 });

  // 기존 ext_id 조회 (중복 스킵)
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
