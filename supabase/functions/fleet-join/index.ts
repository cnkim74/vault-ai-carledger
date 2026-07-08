// 기사가 참여 코드로 Fleet에 참여 — 서비스 롤로 멤버십 추가 (RLS 우회).
// 요청: POST { code }  + Authorization: Bearer <기사 JWT>
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(b: unknown, s = 200) {
  return new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json", ...CORS } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "no_auth" }, 401);

  const body = await req.json().catch(() => ({}));
  const code = String(body.code ?? "").trim().toUpperCase();
  if (!code) return json({ error: "no_code" }, 400);

  // 요청자(기사) 확인
  const ur = await fetch(`${SB_URL}/auth/v1/user`, { headers: { apikey: ANON, Authorization: auth } });
  if (!ur.ok) return json({ error: "invalid_token" }, 401);
  const user = await ur.json();
  const uid = user.id as string;

  // 코드로 조직 찾기 (서비스 롤)
  const svc = { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` };
  const fr = await fetch(`${SB_URL}/rest/v1/fleets?select=id,name&join_code=eq.${encodeURIComponent(code)}`, { headers: svc });
  const fleets = await fr.json();
  if (!Array.isArray(fleets) || fleets.length === 0) return json({ error: "not_found", message: "코드를 찾을 수 없어요" }, 404);
  const fleet = fleets[0];

  // 멤버십 추가 (중복 무시)
  await fetch(`${SB_URL}/rest/v1/fleet_members?on_conflict=fleet_id,user_id`, {
    method: "POST",
    headers: { ...svc, "Content-Type": "application/json", Prefer: "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify({ fleet_id: fleet.id, user_id: uid, email: user.email ?? null, role: "driver" }),
  });

  return json({ ok: true, fleet_id: fleet.id, fleet_name: fleet.name });
});
