// Tesla Fleet API OAuth + 파트너 등록.
// 키는 서버 시크릿(TESLA_CLIENT_ID / TESLA_CLIENT_SECRET)에만 보관.
// action=register → 파트너 등록(도메인 공개키 검증)
// ?code=... (콜백) → 토큰 교환 · 지역 · 차량 id/VIN · 저장 → vault:// 리다이렉트
const CLIENT_ID = Deno.env.get("TESLA_CLIENT_ID") ?? "";
const CLIENT_SECRET = Deno.env.get("TESLA_CLIENT_SECRET") ?? "";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const AUTH = "https://auth.tesla.com/oauth2/v3";
const FLEET_NA = "https://fleet-api.prd.na.vn.cloud.tesla.com";  // 한국=APAC → NA 클러스터
const DOMAIN = "cnkim74.github.io";
const REDIRECT = "https://ftcjeqqdzofuwcphzqnu.supabase.co/functions/v1/tesla-oauth";
// vehicle_charging_cmds → 슈퍼차저 충전/청구 이력 조회 권한 포함
const SCOPE = "openid vehicle_device_data vehicle_charging_cmds offline_access";

function json(b: unknown, s = 200) {
  return new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } });
}

// client_credentials 파트너 토큰
async function partnerToken(): Promise<string> {
  const body = new URLSearchParams({
    grant_type: "client_credentials",
    client_id: CLIENT_ID,
    client_secret: CLIENT_SECRET,
    scope: "openid vehicle_device_data",
    audience: FLEET_NA,
  });
  const r = await fetch(`${AUTH}/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  const d = await r.json();
  if (!d.access_token) throw new Error("partner token: " + JSON.stringify(d));
  return d.access_token;
}

async function saveTokens(fields: Record<string, unknown>) {
  await fetch(`${SB_URL}/rest/v1/tesla_tokens?on_conflict=id`, {
    method: "POST",
    headers: {
      apikey: SB_KEY,
      Authorization: `Bearer ${SB_KEY}`,
      "Content-Type": "application/json",
      Prefer: "resolution=merge-duplicates",
    },
    body: JSON.stringify({ id: "default", updated_at: new Date().toISOString(), ...fields }),
  });
}

Deno.serve(async (req: Request) => {
  if (!CLIENT_ID || !CLIENT_SECRET) return json({ error: "no_key", message: "TESLA_CLIENT_ID/SECRET 미설정" });
  const url = new URL(req.url);
  const action = url.searchParams.get("action");

  try {
    // 1) 파트너 등록 (도메인 공개키 검증)
    if (action === "register") {
      const token = await partnerToken();
      const r = await fetch(`${FLEET_NA}/api/1/partner_accounts`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({ domain: DOMAIN }),
      });
      const d = await r.json().catch(() => ({}));
      return json({ status: r.status, ok: r.ok, result: d });
    }

    // 2) 앱이 열 인증 URL 반환
    if (action === "authurl") {
      const state = crypto.randomUUID();
      const auth = `${AUTH}/authorize?response_type=code&client_id=${encodeURIComponent(CLIENT_ID)}` +
        `&redirect_uri=${encodeURIComponent(REDIRECT)}&scope=${encodeURIComponent(SCOPE)}&state=${state}`;
      return json({ url: auth, state });
    }

    // 3) OAuth 콜백: code → 토큰
    const code = url.searchParams.get("code");
    if (code) {
      const body = new URLSearchParams({
        grant_type: "authorization_code",
        client_id: CLIENT_ID,
        client_secret: CLIENT_SECRET,
        code,
        redirect_uri: REDIRECT,
      });
      const tr = await fetch(`${AUTH}/token`, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body,
      });
      const t = await tr.json();
      if (!t.access_token) {
        return new Response(`토큰 교환 실패: ${JSON.stringify(t)}`, { status: 400 });
      }
      const access = t.access_token, refresh = t.refresh_token;
      const expires = new Date(Date.now() + (t.expires_in ?? 28800) * 1000).toISOString();

      // 지역 조회
      let fleet = FLEET_NA;
      try {
        const rr = await fetch(`${FLEET_NA}/api/1/users/region`, { headers: { Authorization: `Bearer ${access}` } });
        const rd = await rr.json();
        if (rd?.response?.fleet_api_base_url) fleet = rd.response.fleet_api_base_url;
      } catch (_) { /* keep NA */ }

      // 차량 id + VIN
      let vehicleId = "", vin = "";
      try {
        const vr = await fetch(`${fleet}/api/1/vehicles`, { headers: { Authorization: `Bearer ${access}` } });
        const vd = await vr.json();
        const v0 = vd?.response?.[0];
        if (v0) {
          vehicleId = String(v0.id ?? v0.id_s ?? v0.vehicle_id ?? "");
          vin = String(v0.vin ?? "");
        }
      } catch (_) { /* ignore */ }

      await saveTokens({ access_token: access, refresh_token: refresh, expires_at: expires, fleet_base: fleet, vehicle_id: vehicleId, vin });

      // 앱으로 복귀
      return new Response(null, { status: 302, headers: { Location: "vault://tesla?ok=1" } });
    }

    return json({ error: "bad_request", message: "action 또는 code 필요" }, 400);
  } catch (e) {
    return json({ error: "upstream", message: String(e) }, 502);
  }
});
