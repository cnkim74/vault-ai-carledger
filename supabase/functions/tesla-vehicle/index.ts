// 테슬라 차량 데이터(배터리·주행거리·상태) 조회. 사용자별 토큰(id=uid) 사용, 만료 시 갱신.
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

async function dbg(note: string) {
  try {
    await fetch(`${SB_URL}/rest/v1/tesla_debug`, {
      method: "POST", headers: { ...SBH, "Content-Type": "application/json", Prefer: "return=minimal" },
      body: JSON.stringify({ note: note.slice(0, 900) }),
    });
  } catch (_) { /* ignore */ }
}

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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (!CLIENT_ID || !CLIENT_SECRET) return json({ error: "no_key" });

  const uid = await uidFrom(req);
  if (!uid) return json({ error: "no_session", message: "로그인 세션이 필요해요" }, 401);

  const row = await loadToken(uid);
  if (!row || !row.access_token) return json({ error: "not_connected", message: "테슬라 미연결" });

  let access = row.access_token as string;
  const fleet = (row.fleet_base as string) || "https://fleet-api.prd.na.vn.cloud.tesla.com";
  const vid = row.vehicle_id as string;

  if (row.expires_at && new Date(row.expires_at as string).getTime() < Date.now() + 60000) {
    const na = await refresh(uid, row.refresh_token as string);
    if (na) access = na; else return json({ error: "reauth", message: "재로그인 필요" });
  }
  if (!vid) return json({ error: "no_vehicle", message: "차량 없음" });

  const H = { Authorization: `Bearer ${access}` };
  const ep = (loc: boolean) =>
    `${fleet}/api/1/vehicles/${vid}/vehicle_data?endpoints=${encodeURIComponent(
      loc ? "charge_state;vehicle_state;drive_state;location_data" : "charge_state;vehicle_state;drive_state")}`;

  let r = await fetch(ep(true), { headers: H });
  if (r.status === 408) {
    await fetch(`${fleet}/api/1/vehicles/${vid}/wake_up`, { method: "POST", headers: H });
    for (let i = 0; i < 8; i++) {
      await new Promise((res) => setTimeout(res, 3000));
      r = await fetch(ep(true), { headers: H });
      if (r.status !== 408) break;
    }
  }
  // location_data(위치 권한 미부여 등)로 실패하면 위치 제외하고 재시도 → 배터리·상태 동기화는 유지
  if (!r.ok && r.status !== 408) {
    r = await fetch(ep(false), { headers: H });
  }
  if (!r.ok) {
    const t = await r.text();
    return json({ error: "vehicle_unavailable", status: r.status, message: t.slice(0, 200) }, 200);
  }
  const d = await r.json();
  const cs = d?.response?.charge_state ?? {};
  const vs = d?.response?.vehicle_state ?? {};
  const ds = d?.response?.drive_state ?? {};
  const battery = cs.battery_level ?? null;
  const rangeMi = cs.battery_range ?? null;
  const odoMi = vs.odometer ?? null;
  const charging = cs.charging_state ?? null;

  const shift = ds.shift_state ?? null;
  const speed = ds.speed ?? null;
  let status = "parked";
  if (charging === "Charging") status = "charging";
  else if (shift && shift !== "P") status = "driving";
  else if (typeof speed === "number" && speed > 0) status = "driving";

  // 차량 위치 (vehicle_location 권한이 있어야 채워짐)
  const lat = typeof ds.latitude === "number" ? ds.latitude : null;
  const long = typeof ds.longitude === "number" ? ds.longitude : null;
  await dbg(`loc drive_keys=[${Object.keys(ds).join(",")}] lat=${lat} long=${long}`);

  return json({
    connected: true,
    battery,
    rangeKm: rangeMi != null ? Math.round(rangeMi * 1.60934) : null,
    odometerKm: odoMi != null ? Math.round(odoMi * 1.60934) : null,
    name: d?.response?.display_name ?? null,
    charging, shiftState: shift, speed, status,
    lat, long,
    fetchedAt: new Date().toISOString(),
  });
});
