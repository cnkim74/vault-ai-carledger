// Claude(Anthropic) Messages API 프록시 — 키를 서버 시크릿(ANTHROPIC_KEY)에만 보관.
// 앱은 이 함수를 호출하고, 앱·공개리포 어디에도 Anthropic 키가 들어가지 않는다.
// 비용 남용 방지: 모델 화이트리스트 + max_tokens 상한을 서버에서 고정.
//
// 설정: Supabase 대시보드 → Edge Functions → Secrets → ANTHROPIC_KEY 추가
//        또는  supabase secrets set ANTHROPIC_KEY=sk-ant-...
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_KEY");
const ALLOWED_MODELS = new Set(["claude-opus-4-8", "claude-sonnet-5", "claude-haiku-4-5"]);
const MAX_TOKENS_CAP = 1024;

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
  if (!ANTHROPIC_KEY) return json({ error: "no_key", message: "ANTHROPIC_KEY 미설정" });

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }

  const model = ALLOWED_MODELS.has(String(body.model)) ? String(body.model) : "claude-opus-4-8";
  const maxTokens = Math.min(MAX_TOKENS_CAP, Math.max(1, Number(body.max_tokens ?? 512)));

  const payload: Record<string, unknown> = {
    model,
    max_tokens: maxTokens,
    messages: body.messages ?? [],
  };
  if (typeof body.system === "string") payload.system = body.system;

  try {
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": ANTHROPIC_KEY,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
    });
    const data = await r.text();
    return new Response(data, {
      status: r.status,
      headers: { "Content-Type": "application/json", ...CORS },
    });
  } catch (e) {
    return json({ error: "upstream", message: String(e) }, 502);
  }
});
