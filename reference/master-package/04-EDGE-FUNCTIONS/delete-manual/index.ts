import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// PlantMaster Pro — delete-manual
// Fully deletes a manual: storage file + file_metadata + AI index chunks + row.
// Owner/manager only. Verify JWT: ON.

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

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL");
    const secret = serverSecret();
    const authorization = req.headers.get("Authorization") || "";
    const apikey = req.headers.get("apikey") || "";
    const jwt = authorization.replace(/^Bearer\s+/i, "");
    if (!url || !secret) throw Error("Supabase server environment is incomplete");
    if (!jwt || !apikey) return json({ error: "Authentication required" }, 401);

    const userClient = createClient(url, apikey, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false } });
    const ur = await userClient.auth.getUser(jwt);
    const user = ur.data.user;
    if (!user || ur.error) return json({ error: "Invalid or expired session" }, 401);
    const admin = createClient(url, secret, { auth: { persistSession: false, autoRefreshToken: false } });

    const input = await req.json();
    const orgId = String(input.organization_id || "");
    const manualId = String(input.manual_id || "");
    if (!orgId || !manualId) return json({ error: "organization_id and manual_id are required" }, 400);

    const member = await userClient.from("organization_members").select("role").eq("organization_id", orgId).eq("user_id", user.id).eq("active", true).maybeSingle();
    if (member.error || !member.data) return json({ error: "Active company membership required" }, 403);
    if (!["owner", "manager"].includes(String(member.data.role))) return json({ error: "Owner or manager permission required to delete manuals" }, 403);

    const mres = await admin.from("manuals").select("id,storage_path").eq("id", manualId).eq("organization_id", orgId).maybeSingle();
    if (mres.error || !mres.data) return json({ error: "Manual not found" }, 404);
    const path = String(mres.data.storage_path || "");

    // storage file (ignore if already gone)
    if (path) await admin.storage.from("plant-files").remove([path]).catch(() => {});
    // usage/metadata row
    if (path) await admin.from("file_metadata").delete().eq("object_path", path);
    // AI index chunks
    await admin.from("document_chunks").delete().eq("manual_id", manualId);
    // the manual row
    const del = await admin.from("manuals").delete().eq("id", manualId).eq("organization_id", orgId);
    if (del.error) return json({ error: "Delete failed: " + del.error.message }, 500);
    return json({ ok: true, deleted: "manual + file + AI index" });
  } catch (e) {
    return json({ error: String((e as any)?.message || e) }, 500);
  }
});
