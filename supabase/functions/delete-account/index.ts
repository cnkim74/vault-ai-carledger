// 로그인 사용자가 본인 계정과 데이터를 삭제 (App Store 심사 요건).
// 요청: POST + Authorization: Bearer <사용자 JWT>
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

  // 요청자 확인
  const ur = await fetch(`${SB_URL}/auth/v1/user`, { headers: { apikey: ANON, Authorization: auth } });
  if (!ur.ok) return json({ error: "invalid_token" }, 401);
  const user = await ur.json();
  const uid = user.id as string;

  const svc = { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, "Content-Type": "application/json" };
  const del = (path: string) => fetch(`${SB_URL}/rest/v1/${path}`, { method: "DELETE", headers: { ...svc, Prefer: "return=minimal" } });

  // 소유 조직 삭제 (차량·기록·배정·멤버 CASCADE) + 타 조직 내 본인 흔적 정리
  await del(`fleets?owner_id=eq.${uid}`);
  await del(`fleet_members?user_id=eq.${encodeURIComponent(uid)}`);
  await del(`fleet_assignments?user_id=eq.${encodeURIComponent(uid)}`);

  // 인증 계정 삭제 (서비스 롤 admin API)
  const dr = await fetch(`${SB_URL}/auth/v1/admin/users/${uid}`, { method: "DELETE", headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` } });
  if (!dr.ok && dr.status !== 200 && dr.status !== 204) {
    return json({ error: "delete_failed", status: dr.status }, 500);
  }
  return json({ ok: true });
});
