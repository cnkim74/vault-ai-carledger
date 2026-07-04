// 주변 전기차 충전소 프록시 — 한국환경공단(KECO) 실시간 충전기 정보.
// apis.data.go.kr/B552584/EvCharger/getChargerInfo (lat/lng + 실시간 stat)
// 위경도로 가장 가까운 시도(zcode)를 고른 뒤 반경 내 충전소를 거리순 정렬.
//
// ⚠️ 공개 리포이므로 이 파일에는 키를 넣지 않습니다.
//    설정: Supabase 대시보드 → Edge Functions → Secrets → KECO_KEY
//          (공공데이터포털 getChargerInfo 서비스키, "인코딩" 버전)
//          또는  supabase secrets set KECO_KEY=...
const KECO_KEY = Deno.env.get("KECO_KEY");

// 시도 zcode → 대표 좌표(WGS84)
const SIDO: { code: string; lat: number; lng: number }[] = [
  { code: "11", lat: 37.566, lng: 126.978 }, { code: "26", lat: 35.180, lng: 129.075 },
  { code: "27", lat: 35.871, lng: 128.601 }, { code: "28", lat: 37.456, lng: 126.705 },
  { code: "29", lat: 35.160, lng: 126.851 }, { code: "30", lat: 36.350, lng: 127.385 },
  { code: "31", lat: 35.539, lng: 129.311 }, { code: "36", lat: 36.480, lng: 127.289 },
  { code: "41", lat: 37.410, lng: 127.520 }, { code: "42", lat: 37.860, lng: 128.310 },
  { code: "43", lat: 36.800, lng: 127.700 }, { code: "44", lat: 36.620, lng: 126.850 },
  { code: "45", lat: 35.720, lng: 127.100 }, { code: "46", lat: 34.860, lng: 126.990 },
  { code: "47", lat: 36.400, lng: 128.900 }, { code: "48", lat: 35.260, lng: 128.200 },
  { code: "50", lat: 33.490, lng: 126.530 },
];

// 급속 유형 chgerType
const FAST = new Set(["01", "03", "04", "05", "06", "08"]);

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status, headers: { "Content-Type": "application/json", ...CORS },
  });
}

function haversine(la1: number, lo1: number, la2: number, lo2: number): number {
  const R = 6371000, t = Math.PI / 180;
  const dLa = (la2 - la1) * t, dLo = (lo2 - lo1) * t;
  const a = Math.sin(dLa / 2) ** 2 +
    Math.cos(la1 * t) * Math.cos(la2 * t) * Math.sin(dLo / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (!KECO_KEY) return json({ error: "no_key", message: "KECO_KEY 미설정" });

  let lat: number, lon: number, radius: number;
  try {
    const b = await req.json();
    lat = Number(b.lat); lon = Number(b.lon);
    radius = Math.min(10000, Math.max(300, Number(b.radius ?? 3000)));
    if (!isFinite(lat) || !isFinite(lon)) throw new Error("bad coords");
  } catch {
    return json({ error: "bad_request" }, 400);
  }

  let zcode = "11", best = Infinity;
  for (const s of SIDO) {
    const d = haversine(lat, lon, s.lat, s.lng);
    if (d < best) { best = d; zcode = s.code; }
  }

  const url = `http://apis.data.go.kr/B552584/EvCharger/getChargerInfo` +
    `?serviceKey=${KECO_KEY}&pageNo=1&numOfRows=9999&zcode=${zcode}&dataType=JSON`;

  try {
    const r = await fetch(url);
    const data = await r.json();
    const bodyObj = data?.response?.body ?? data;
    const raw = bodyObj?.items?.item ?? bodyObj?.items ?? [];
    const list: Record<string, unknown>[] = Array.isArray(raw) ? raw : [];

    type Agg = { name: string; addr: string; lat: number; lng: number; available: number; total: number; fast: boolean };
    const byStat = new Map<string, Agg>();
    for (const o of list) {
      const la = Number(o.lat), lo = Number(o.lng);
      if (!isFinite(la) || !isFinite(lo)) continue;
      const d = haversine(lat, lon, la, lo);
      if (d > radius) continue;
      const id = String(o.statId ?? o.statNm ?? "");
      const a = byStat.get(id) ?? {
        name: String(o.statNm ?? ""), addr: String(o.addr ?? ""),
        lat: la, lng: lo, available: 0, total: 0, fast: false,
      };
      a.total += 1;
      if (String(o.stat) === "2") a.available += 1;   // 2 = 충전대기(가능)
      if (FAST.has(String(o.chgerType))) a.fast = true;
      byStat.set(id, a);
    }

    const chargers = [...byStat.entries()]
      .map(([id, a]) => ({
        id, name: a.name, addr: a.addr,
        distanceMeters: haversine(lat, lon, a.lat, a.lng),
        available: a.available, total: a.total, fast: a.fast,
      }))
      .sort((x, y) => x.distanceMeters - y.distanceMeters)
      .slice(0, 30);

    return json({ chargers, zcode, fetchedAt: new Date().toISOString() });
  } catch (e) {
    return json({ error: "upstream", message: String(e) }, 502);
  }
});
