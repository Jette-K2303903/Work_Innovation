// Supabase Edge Function : kakao
// 기사님 페이지(도착 예상시간 계산) · 실시간 대시보드(위치 → 동 이름)가 호출합니다.
// 카카오 REST API 키는 Supabase 의 Secrets 에 KAKAO_REST_KEY 라는 이름으로만 보관합니다 (코드/사이트에 넣지 않음).
//
// 요청 (POST, JSON)
//   { "action": "route",  "points": [ {x,y} 또는 {address}, {x,y}, ... ] }   → { durations: [초...], distances: [m...], origin: {x,y} }
//   { "action": "region", "x": 경도, "y": 위도 }                              → { name: "부산 해운대구 우동" }
//   { "action": "geocode", "addresses": ["주소1", "주소2", ...] }  (최대 50개)   → { results: [ { ok, x, y, matched, via } ] }
//        주소 검증용. 전체 주소로 못 찾으면 괄호·층·상호 등 뒤쪽 상세를 떼고 건물 주소까지만 다시 검색 (via: "full" | "trimmed")

const KEY = Deno.env.get("KAKAO_REST_KEY") ?? "";
const ALLOWED = ["https://work-innovation.onrender.com", "http://localhost"];   // 호출을 허용할 사이트

function cors(req: Request) {
  const origin = req.headers.get("origin") ?? "";
  const ok = ALLOWED.some((a) => origin === a || origin.startsWith(a + ":"));
  return {
    "Access-Control-Allow-Origin": ok ? origin : ALLOWED[0],
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}
const json = (req: Request, body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors(req), "Content-Type": "application/json" } });
const kakao = (url: string, init: RequestInit = {}) =>
  fetch(url, { ...init, headers: { Authorization: `KakaoAK ${KEY}`, "Content-Type": "application/json", ...(init.headers ?? {}) } });
const isNum = (v: unknown) => typeof v === "number" && isFinite(v);

type Pt = { x?: number; y?: number; address?: string };

async function geocode(address: string): Promise<{ x: number; y: number } | null> {
  const r = await kakao("https://dapi.kakao.com/v2/local/search/address.json?size=1&query=" + encodeURIComponent(address));
  if (!r.ok) return null;
  const d = (await r.json()).documents?.[0];
  return d ? { x: parseFloat(d.x), y: parseFloat(d.y) } : null;
}

// 주소 검증 : 전체 주소 → 괄호 제거 → 도로명+건물번호(또는 동/리+번지)까지만 순서로 검색
function addressCandidates(addr: string): string[] {
  const s = String(addr ?? "").replace(/\s+/g, " ").trim();
  if (!s) return [];
  const out = [s];
  const noParen = s.replace(/\([^)]*\)/g, " ").replace(/\s+/g, " ").trim();
  out.push(noParen);
  const road = noParen.match(/^(.*?(?:로|길)\s*\d+(?:-\d+)?(?:번길\s*\d+(?:-\d+)?)?)/);
  if (road) out.push(road[1]);
  const lot = noParen.match(/^(.*?(?:동|리|가|읍|면)\s*(?:산\s*)?\d+(?:-\d+)?)/);
  if (lot) out.push(lot[1]);
  return [...new Set(out.filter(Boolean))];
}
async function verifyAddress(addr: string) {
  const list = addressCandidates(addr);
  for (let i = 0; i < list.length; i++) {
    const r = await kakao("https://dapi.kakao.com/v2/local/search/address.json?size=1&query=" + encodeURIComponent(list[i]));
    if (r.status === 429) throw new Error("kakao rate limit");
    if (!r.ok) continue;
    const d = (await r.json()).documents?.[0];
    if (d) return { ok: true, x: parseFloat(d.x), y: parseFloat(d.y), matched: d.address_name ?? list[i], via: i === 0 ? "full" : "trimmed" };
  }
  return { ok: false };
}

// 한 번에 출발지 + 경유지 30 + 목적지 = 32개 지점까지. 그보다 많으면 나눠서 호출.
async function legs(points: { x: number; y: number }[]) {
  const durations: number[] = [], distances: number[] = [];
  for (let i = 0; i < points.length - 1; i += 31) {
    const chunk = points.slice(i, i + 32);
    const body: Record<string, unknown> = { origin: chunk[0], destination: chunk[chunk.length - 1], priority: "RECOMMEND", summary: true };
    if (chunk.length > 2) body.waypoints = chunk.slice(1, -1);
    const r = await kakao("https://apis-navi.kakaomobility.com/v1/waypoints/directions", { method: "POST", body: JSON.stringify(body) });
    if (!r.ok) throw new Error(`kakao directions ${r.status}: ${(await r.text()).slice(0, 200)}`);
    const route = (await r.json()).routes?.[0];
    if (!route || route.result_code !== 0) throw new Error(`route failed: ${route?.result_code} ${route?.result_msg ?? ""}`);
    const sections = route.sections ?? [];
    if (sections.length !== chunk.length - 1) throw new Error("unexpected sections");
    for (const s of sections) { durations.push(s.duration); distances.push(s.distance); }
  }
  return { durations, distances };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(req) });
  if (req.method !== "POST") return json(req, { error: "POST only" }, 405);
  if (!KEY) return json(req, { error: "KAKAO_REST_KEY secret is not set" }, 500);
  try {
    const b = await req.json();
    if (b.action === "region") {
      if (!isNum(b.x) || !isNum(b.y)) return json(req, { error: "x, y required" }, 400);
      const r = await kakao(`https://dapi.kakao.com/v2/local/geo/coord2regioncode.json?x=${b.x}&y=${b.y}`);
      if (!r.ok) return json(req, { error: `kakao region ${r.status}` }, 502);
      const docs = (await r.json()).documents ?? [];
      const d = docs.find((x: { region_type: string }) => x.region_type === "H") ?? docs[0];
      return json(req, { name: d?.address_name ?? "" });
    }
    if (b.action === "geocode") {
      const list: string[] = Array.isArray(b.addresses) ? b.addresses.slice(0, 50).map((a: unknown) => String(a ?? "")) : [];
      const results: unknown[] = new Array(list.length);
      let next = 0;
      await Promise.all(Array.from({ length: Math.min(5, list.length) }, async () => {   // 동시에 5개씩
        while (next < list.length) { const i = next++; results[i] = await verifyAddress(list[i]); }
      }));
      return json(req, { results });
    }
    if (b.action === "route") {
      const pts: Pt[] = Array.isArray(b.points) ? b.points : [];
      if (pts.length < 2 || pts.length > 120) return json(req, { error: "points: 2 ~ 120" }, 400);
      const resolved: { x: number; y: number }[] = [];
      for (const p of pts) {
        if (isNum(p.x) && isNum(p.y)) resolved.push({ x: p.x as number, y: p.y as number });
        else if (p.address) {
          const g = await geocode(p.address);
          if (!g) return json(req, { error: "address not found: " + p.address }, 422);
          resolved.push(g);
        } else return json(req, { error: "each point needs x,y or address" }, 400);
      }
      return json(req, { ...(await legs(resolved)), origin: resolved[0] });
    }
    return json(req, { error: "unknown action" }, 400);
  } catch (e) {
    return json(req, { error: String((e as Error)?.message ?? e) }, 502);
  }
});
