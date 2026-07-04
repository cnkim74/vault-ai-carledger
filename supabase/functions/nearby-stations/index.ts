// 주변 주유소 프록시 — 한국석유공사 오피넷 aroundAll.do
// WGS84(lat/lon) → KATEC(TM128, Bessel) 변환 후 오피넷 실시간 유가 조회.
//
// ⚠️ 공개 리포이므로 이 파일에는 키를 넣지 않습니다.
//    배포는 Supabase MCP/CLI로 하고, 키는 Edge Function 시크릿으로 설정하세요:
//      supabase secrets set OPINET_KEY=발급받은키
//    (오피넷 무료 실시간 API 키: https://www.opinet.co.kr)
import proj4 from "https://esm.sh/proj4@2.11.0";

const OPINET_KEY = Deno.env.get("OPINET_KEY");

const KATEC =
  "+proj=tmerc +lat_0=38 +lon_0=128 +k=0.9999 +x_0=400000 +y_0=600000 " +
  "+ellps=bessel +units=m +no_defs " +
  "+towgs84=-115.80,474.99,674.11,1.16,-2.31,-1.63,6.43";

const BRAND: Record<string, string> = {
  SKE: "SK에너지", GSC: "GS칼텍스", HDO: "현대오일뱅크", SOL: "S-OIL",
  RTO: "자영알뜰", RTX: "고속도로알뜰", NHO: "농협알뜰", ETC: "자가상표",
  E1G: "E1", SKG: "SK가스",
};

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  if (!OPINET_KEY) return json({ error: "no_key", message: "OPINET_KEY 미설정" });

  let lat: number, lon: number, fuel: string, radius: number;
  try {
    const b = await req.json();
    lat = Number(b.lat);
    lon = Number(b.lon);
    fuel = String(b.fuel ?? "B027");
    radius = Math.min(5000, Math.max(100, Number(b.radius ?? 3000)));
    if (!isFinite(lat) || !isFinite(lon)) throw new Error("bad coords");
  } catch {
    return json({ error: "bad_request" }, 400);
  }

  const [x, y] = proj4("WGS84", KATEC, [lon, lat]);

  const base = "https://www.opinet.co.kr/api";
  const aroundURL =
    `${base}/aroundAll.do?code=${OPINET_KEY}&out=json&sort=1&prodcd=${fuel}` +
    `&x=${x.toFixed(3)}&y=${y.toFixed(3)}&radius=${radius}`;
  const avgURL = `${base}/avgAllPrice.do?code=${OPINET_KEY}&out=json`;

  try {
    const [aroundRes, avgRes] = await Promise.all([fetch(aroundURL), fetch(avgURL)]);
    const around = await aroundRes.json();
    const avg = await avgRes.json();

    const oilList = around?.RESULT?.OIL ?? [];
    const stations = oilList.map((o: Record<string, unknown>) => ({
      id: String(o.UNI_ID ?? ""),
      name: String(o.OS_NM ?? ""),
      brand: BRAND[String(o.POLL_DIV_CD ?? "")] ?? String(o.POLL_DIV_CD ?? ""),
      price: Math.round(Number(o.PRICE ?? 0)),
      distanceMeters: Number(o.DISTANCE ?? 0),
    })).filter((s: { price: number }) => s.price > 0);

    const avgList = avg?.RESULT?.OIL ?? [];
    const averages: Record<string, number> = {};
    for (const a of avgList) {
      averages[String((a as Record<string, unknown>).PRODCD)] =
        Math.round(Number((a as Record<string, unknown>).PRICE));
    }

    return json({ stations, averages, fuel, fetchedAt: new Date().toISOString() });
  } catch (e) {
    return json({ error: "upstream", message: String(e) }, 502);
  }
});
