// 좌표 → 한글 주소(도로명 우선).
// 1순위: 카카오 coord2address (KAKAO_REST_KEY 시크릿 있을 때, 도로명 가장 정확)
// 2순위: OpenStreetMap Nominatim (키 불필요)
const KAKAO_KEY = Deno.env.get("KAKAO_REST_KEY");

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(b: unknown, s = 200) {
  return new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json", ...CORS } });
}

async function kakao(lat: number, long: number): Promise<{ road: string | null; jibun: string | null }> {
  if (!KAKAO_KEY) return { road: null, jibun: null };
  try {
    const url = `https://dapi.kakao.com/v2/local/geo/coord2address.json?x=${long}&y=${lat}`;
    const r = await fetch(url, { headers: { Authorization: `KakaoAK ${KAKAO_KEY}` } });
    if (!r.ok) return { road: null, jibun: null };
    const d = await r.json();
    const doc = d?.documents?.[0];
    return {
      road: doc?.road_address?.address_name ?? null,
      jibun: doc?.address?.address_name ?? null,
    };
  } catch (_) { return { road: null, jibun: null }; }
}

async function osm(lat: number, long: number): Promise<string | null> {
  try {
    const url = `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${lat}&lon=${long}` +
      `&accept-language=ko&zoom=18&addressdetails=1`;
    const r = await fetch(url, { headers: { "User-Agent": "Wheelet-CarLedger/1.0 (support@wheelet.app)" } });
    if (!r.ok) return null;
    const d = await r.json();
    const a = d?.address ?? {};
    const city = a.city || a.county || a.town || a.city_district || a.province || a.state;
    const gu = a.borough || a.city_district;
    const road = a.road;
    const num = a.house_number;
    const dong = a.suburb || a.neighbourhood || a.quarter || a.village;
    const parts: string[] = [];
    if (city) parts.push(city);
    if (gu && gu !== city) parts.push(gu);
    if (road) parts.push(road + (num ? ` ${num}` : ""));
    else if (dong) parts.push(dong);
    return parts.length ? parts.join(" ") : (d?.display_name ?? null);
  } catch (_) { return null; }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const body = await req.json().catch(() => ({}));
  const lat = Number(body.lat), long = Number(body.long);
  if (!isFinite(lat) || !isFinite(long)) return json({ error: "bad_request" }, 400);

  // 도로명 우선: 카카오 도로명 → OSM(도로명 기반) → 카카오 지번
  const kk = await kakao(lat, long);
  const address = kk.road ?? (await osm(lat, long)) ?? kk.jibun;
  if (!address) return json({ error: "not_found", address: null });
  return json({ address });
});
