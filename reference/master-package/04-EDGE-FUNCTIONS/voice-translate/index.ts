
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// PlantMaster Pro v4.13 — voice-translate
// Converts spoken Urdu dictation (transcribed by the browser) into technical English.
// Called ONLY from the app with a valid user JWT. Keep "Verify JWT" ON for this function.

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization,x-client-info,apikey,content-type" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

function serverSecret() {
  const d = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SECRET_KEY");
  if (d) return d;
  try {
    const p = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}");
    const v = (Array.isArray(p) ? p : Object.values(p || {})).flatMap((x: any) => typeof x === "string" ? [x] : Object.values(x || {}).filter((y): y is string => typeof y === "string"));
    const modern = v.find((x: string) => x.startsWith("sb_secret_"));
    if (modern) return modern;
    return v.find((x: string) => { try { return JSON.parse(atob(x.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))).role === "service_role"; } catch { return false; } });
  } catch { return; }
}

async function callGemini(key: string, body: any) {
  let response: Response | null = null, raw = "", model = "gemini-3.1-flash-lite";
  for (const m of ["gemini-3.1-flash-lite", "gemini-3.7-flash"]) {
    model = m;
    response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${m}:generateContent?key=${encodeURIComponent(key)}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
    raw = await response.text();
    if (response.ok) break;
    if (response.status === 429) throw Error(`Gemini quota unavailable (429): ${raw.slice(0, 900)}`);
    if (response.status !== 503) break;
  }
  if (!response?.ok) throw Error(`Gemini unavailable (${response?.status || 500}): ${raw.slice(0, 900)}`);
  return { data: JSON.parse(raw), model };
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const key = Deno.env.get("GEMINI_API_KEY");
    const url = Deno.env.get("SUPABASE_URL");
    const secret = serverSecret();
    const authorization = req.headers.get("Authorization") || "";
    const apikey = req.headers.get("apikey") || "";
    const jwt = authorization.replace(/^Bearer\s+/i, "");
    if (!key) throw Error("GEMINI_API_KEY secret is missing");
    if (!url || !secret) throw Error("Supabase server environment is incomplete");
    if (!jwt || !apikey) return json({ error: "Authentication required" }, 401);

    const userClient = createClient(url, apikey, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false } });
    const ur = await userClient.auth.getUser(jwt);
    const user = ur.data.user;
    if (!user || ur.error) return json({ error: "Invalid or expired session" }, 401);

    const input = await req.json();
    const text = String(input.text || "").trim();
    const mode = String(input.mode || "");
    if (!text) return json({ error: "text is required" }, 400);
    if (text.length > 4000) return json({ error: "text is too long" }, 400);

    // Defensive: only 'ur'-mode calls are converted (the client only sends mode:'ur')
    if (mode !== "ur") return json({ ok: true, english: text, original: text, translated: false, model: null });

    // Any active company member may use voice typing (input utility, no AI quota reserved)
    const admin = createClient(url, secret, { auth: { persistSession: false, autoRefreshToken: false } });
    const member = await userClient.from("organization_members").select("organization_id").eq("user_id", user.id).eq("active", true).maybeSingle();
    if (member.error || !member.data) return json({ error: "Active company membership required" }, 403);

    const { data, model } = await callGemini(key, {
      contents: [{ role: "user", parts: [{ text: `The text below was dictated by a Pakistani plant worker and transcribed by a voice recognizer. It is in Urdu and may appear as Urdu script (Nastaliq) or as Roman Urdu (Urdu words written with English letters, e.g. "log book likhni hai"). Convert it into concise technical English (e.g. "log book likhni hai" => "Need to write the log book"). Keep machine model numbers, units, alarm codes and brand names exactly as spoken. If the input is already plain English with no Urdu, return it unchanged. Return ONLY the final English text - no quotes, no labels, no preamble.\n\n${text}` }] }],
      generationConfig: { temperature: 0, maxOutputTokens: 500 }
    });
    const out = (data.candidates?.[0]?.content?.parts?.map((x: any) => x.text || "").join("") || "").trim();
    return json({ ok: true, english: out || text, original: text, translated: !!out, model });
  } catch (e) {
    return json({ error: String((e as any)?.message || e) }, 500);
  }
});
