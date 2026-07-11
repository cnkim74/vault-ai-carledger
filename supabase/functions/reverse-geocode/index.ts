// 좌표 → 한글 주소(도로명 우선). 카카오 로컬 API 사용.
// 설정: Supabase 시크릿 KAKAO_REST_KEY (카카오 developers 앱의 REST API 키)
const KAKAO_KEY = Deno.env.get("KAKAO_REST_KEY");

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(b: unknown, s = 200) {
  return new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json", ...CORS } });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (!KAKAO_KEY) return json({ error: "no_key", message: "KAKAO_REST_KEY 미설정" });

  const body = await req.json().catch(() => ({}));
  const lat = Number(body.lat), long = Number(body.long);
  if (!isFinite(lat) || !isFinite(long)) return json({ error: "bad_request" }, 400);

  const url = `https://dapi.kakao.com/v2/local/geo/coord2address.json?x=${long}&y=${lat}`;
  const r = await fetch(url, { headers: { Authorization: `KakaoAK ${KAKAO_KEY}` } });
  if (!r.ok) {
    const t = await r.text();
    return json({ error: "kakao_failed", status: r.status, message: t.slice(0, 200) });
  }
  const d = await r.json();
  const doc = d?.documents?.[0];
  const road = doc?.road_address?.address_name ?? null;   // 도로명 주소
  const jibun = doc?.address?.address_name ?? null;        // 지번 주소
  return json({ address: road || jibun || null, road, jibun });
});
