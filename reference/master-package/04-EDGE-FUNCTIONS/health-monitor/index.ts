import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

serve(async (request) => {
  const expected = Deno.env.get("HEALTH_MONITOR_TOKEN");
  if (!expected || request.headers.get("x-monitor-token") !== expected) return json({ error: "Unauthorized" }, 401);
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const geminiKey = Deno.env.get("GEMINI_API_KEY");
  if (!url || !serviceKey) return json({ error: "Server environment incomplete" }, 500);
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const results: Record<string, { ok: boolean; latency_ms: number; error?: string }> = {};

  async function check(name: string, task: () => Promise<void>) {
    const started = Date.now();
    try {
      await task();
      results[name] = { ok: true, latency_ms: Date.now() - started };
      await admin.from("system_incidents").update({ status: "resolved", resolved_at: new Date().toISOString(), last_seen_at: new Date().toISOString() }).eq("component", name).eq("event_type", "health_check_failed").neq("status", "resolved");
    } catch (error) {
      const message = String(error?.message || error).slice(0, 500);
      results[name] = { ok: false, latency_ms: Date.now() - started, error: message };
      const existing = await admin.from("system_incidents").select("id").eq("component", name).eq("event_type", "health_check_failed").neq("status", "resolved").limit(1).maybeSingle();
      if (existing.data) await admin.from("system_incidents").update({ last_seen_at: new Date().toISOString(), message, severity: "critical" }).eq("id", existing.data.id);
      else await admin.from("system_incidents").insert({ severity: "critical", component: name, event_type: "health_check_failed", message, details: { latency_ms: Date.now() - started } });
    }
  }

  await check("database", async () => {
    const r = await admin.from("organizations").select("id", { count: "exact", head: true });
    if (r.error) throw r.error;
  });
  await check("storage", async () => {
    const r = await admin.storage.from("plant-files").list("", { limit: 1 });
    if (r.error) throw r.error;
  });
  await check("gemini_api", async () => {
    if (!geminiKey) throw new Error("GEMINI_API_KEY missing");
    const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite?key=${encodeURIComponent(geminiKey)}`);
    if (!r.ok) throw new Error(`Gemini model check failed: ${r.status} ${(await r.text()).slice(0, 250)}`);
  });

  await admin.rpc("control_maintenance_tick");
  const ok = Object.values(results).every((r) => r.ok);
  return json({ ok, checked_at: new Date().toISOString(), results }, ok ? 200 : 503);
});
