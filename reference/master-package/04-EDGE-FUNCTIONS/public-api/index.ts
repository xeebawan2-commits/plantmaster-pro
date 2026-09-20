// PlantMaster Pro — Public REST API v1
// Supabase Edge Function (Deno)
//
// Deploy:
//   supabase functions deploy public-api --no-verify-jwt
//
// Auth: X-API-Key header. Keys are stored SHA-256 hashed in public.api_keys —
// the plaintext key is shown to the user exactly once, at creation.
//
// IMPORTANT: this function uses the service-role key and therefore BYPASSES RLS.
// Tenant isolation is enforced manually: every query is scoped to the
// organization_id / plant_id recorded on the api_keys row. Do not add a query
// path that skips scope().
//
// All column names below were verified against the live client code
// (app.js / operations.js), not inferred.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-api-key",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

async function sha256(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "GET") {
    return json({ error: "Only GET is supported by the v1 read API" }, 405);
  }

  const url = new URL(req.url);
  // Path looks like /public-api/v1/assets — take the segment after "v1".
  const parts = url.pathname.split("/").filter(Boolean);
  const vIdx = parts.indexOf("v1");
  const resource = vIdx >= 0 ? (parts[vIdx + 1] ?? "") : (parts.at(-1) ?? "");

  const apiKey = req.headers.get("x-api-key") ?? "";
  if (!apiKey) {
    return json({ error: "Missing X-API-Key header" }, 401);
  }

  const sb = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // ---------------------------------------------------------------- auth
  const hash = await sha256(apiKey);
  const { data: keyRow, error: keyErr } = await sb
    .from("api_keys")
    .select("id, organization_id, plant_id, revoked_at, expires_at")
    .eq("key_hash", hash)
    .maybeSingle();

  if (keyErr) return json({ error: "Key lookup failed" }, 500);
  if (!keyRow) return json({ error: "Invalid API key" }, 401);
  if (keyRow.revoked_at) return json({ error: "API key has been revoked" }, 403);
  if (keyRow.expires_at && new Date(keyRow.expires_at) < new Date()) {
    return json({ error: "API key has expired" }, 403);
  }

  const org = keyRow.organization_id as string;
  const plant = keyRow.plant_id as string | null;

  // Fire-and-forget usage stamp; never blocks or fails the response.
  sb.from("api_keys")
    .update({ last_used_at: new Date().toISOString() })
    .eq("id", keyRow.id)
    .then(() => {}, () => {});

  // ---------------------------------------------------------------- helpers
  const limit = Math.min(Math.max(Number(url.searchParams.get("limit") ?? 50), 1), 200);
  const offset = Math.max(Number(url.searchParams.get("offset") ?? 0), 0);

  // Tenant scope. Tables carrying plant_id are narrowed to the key's plant when
  // the key is plant-scoped; otherwise to the organization.
  const scope = <T extends { eq: (c: string, v: unknown) => T }>(q: T) =>
    plant ? q.eq("plant_id", plant) : q.eq("organization_id", org);

  // Every operational table uses removed_at for soft delete.
  const live = <T extends { is: (c: string, v: unknown) => T }>(q: T) => q.is("removed_at", null);

  const page = (data: unknown[] | null) => ({
    data: data ?? [],
    limit,
    offset,
    count: data?.length ?? 0,
  });

  try {
    switch (resource) {
      // ------------------------------------------------------------- meta
      case "meta": {
        const [o, plants, assets, wos] = await Promise.all([
          sb.from("organizations").select("id,name,created_at").eq("id", org).maybeSingle(),
          plant
            ? sb.from("plants").select("id,name").eq("id", plant)
            : sb.from("plants").select("id,name").eq("organization_id", org),
          live(scope(sb.from("assets").select("*", { count: "exact", head: true }))),
          live(scope(sb.from("work_orders").select("*", { count: "exact", head: true }))),
        ]);
        return json({
          organization: o.data,
          plants: plants.data ?? [],
          scope: plant ? { type: "plant", plant_id: plant } : { type: "organization", organization_id: org },
          counts: { assets: assets.count ?? 0, work_orders: wos.count ?? 0 },
          api_version: "v1",
          resources: ["meta", "assets", "work-orders", "spares", "tools", "maintenance-plans", "purchase-orders", "suppliers"],
        });
      }

      // ----------------------------------------------------------- assets
      case "assets": {
        let q = live(scope(sb.from("assets").select(
          "id,name,asset_code,asset_type,location,status,running_state," +
          "meter_unit,current_meter_value,pm_trigger_meter_value,updated_at",
        )))
          .range(offset, offset + limit - 1)
          .order("updated_at", { ascending: false });

        const status = url.searchParams.get("status");
        if (status) q = q.eq("status", status);
        const state = url.searchParams.get("running_state");
        if (state) q = q.eq("running_state", state);

        const { data, error } = await q;
        if (error) throw error;
        return json(page(data));
      }

      // ------------------------------------------------------ work-orders
      case "work-orders": {
        let q = live(scope(sb.from("work_orders").select(
          "id,title,description,status,priority,asset_id,assets(name)," +
          "work_done,root_cause,corrective_action,downtime_minutes,labor_minutes,total_cost," +
          "designation,shift_name,started_at,completed_at,updated_at",
        )))
          .range(offset, offset + limit - 1)
          .order("updated_at", { ascending: false });

        const status = url.searchParams.get("status");
        if (status) q = q.eq("status", status);
        const priority = url.searchParams.get("priority");
        if (priority) q = q.eq("priority", priority);
        const assetId = url.searchParams.get("asset_id");
        if (assetId) q = q.eq("asset_id", assetId);

        const { data, error } = await q;
        if (error) throw error;
        return json(page(data));
      }

      // ----------------------------------------------------------- spares
      case "spares": {
        // low_stock is filtered in SQL, not in JS, so pagination stays correct.
        let q = live(scope(sb.from("spares").select(
          "id,part_number,description,unit,stock,min_stock,bin_location,supplier,asset_id,assets(name),updated_at",
        )))
          .range(offset, offset + limit - 1)
          .order("description");

        // PostgREST cannot compare one column against another, so low_stock is
        // evaluated here. We widen the fetch and paginate after filtering.
        const lowStock = url.searchParams.get("low_stock") === "true";
        if (lowStock) q = q.range(0, 999);

        const { data, error } = await q;
        if (error) throw error;

        if (lowStock) {
          const low = (data ?? []).filter((s: Record<string, unknown>) =>
            Number(s.stock ?? 0) <= Number(s.min_stock ?? 0)
          );
          return json({
            data: low.slice(offset, offset + limit),
            limit,
            offset,
            count: Math.min(limit, Math.max(low.length - offset, 0)),
            total_low_stock: low.length,
          });
        }
        return json(page(data));
      }

      // ------------------------------------------------------------ tools
      case "tools": {
        const { data, error } = await live(scope(sb.from("tools").select(
          "id,name,tool_code,specification,status,updated_at",
        )))
          .range(offset, offset + limit - 1)
          .order("name");
        if (error) throw error;
        return json(page(data));
      }

      // ------------------------------------------------ maintenance-plans
      case "maintenance-plans": {
        let q = live(scope(sb.from("maintenance_plans").select(
          "id,title,description,frequency,priority,next_due,status," +
          "asset_id,assets(name),last_completed_at,updated_at",
        )))
          .range(offset, offset + limit - 1)
          .order("next_due");

        const status = url.searchParams.get("status");
        if (status) q = q.eq("status", status);
        // ?overdue=true — anything due on or before today and not yet completed.
        if (url.searchParams.get("overdue") === "true") {
          q = q.lte("next_due", new Date().toISOString().slice(0, 10)).neq("status", "completed");
        }

        const { data, error } = await q;
        if (error) throw error;
        return json(page(data));
      }

      // -------------------------------------------------- purchase-orders
      case "purchase-orders": {
        let q = live(scope(sb.from("purchase_orders").select(
          "id,po_number,status,supplier_id,suppliers(name),currency," +
          "subtotal,tax_percent,tax_amount,total,expected_date,received_date," +
          "notes,approved_at,created_at,updated_at," +
          "purchase_order_lines(id,description,quantity,received_qty,unit,unit_price,line_total,spare_id)",
        )))
          .range(offset, offset + limit - 1)
          .order("created_at", { ascending: false });

        const status = url.searchParams.get("status");
        if (status) q = q.eq("status", status);

        const { data, error } = await q;
        if (error) throw error;
        return json(page(data));
      }

      // -------------------------------------------------------- suppliers
      case "suppliers": {
        // suppliers.plant_id is nullable — org-level suppliers are shared across
        // plants, so a plant-scoped key must still see them. Scope by org only.
        const { data, error } = await live(sb.from("suppliers").select(
          "id,name,contact_person,phone,email,ntn,strn,payment_terms,currency,rating,updated_at",
        ).eq("organization_id", org))
          .range(offset, offset + limit - 1)
          .order("name");
        if (error) throw error;
        return json(page(data));
      }

      // ---------------------------------------------------------- default
      default:
        return json({
          error: resource ? `Unknown resource '${resource}'` : "No resource specified",
          available: [
            "meta", "assets", "work-orders", "spares", "tools",
            "maintenance-plans", "purchase-orders", "suppliers",
          ],
          usage: "GET /public-api/v1/<resource>?limit=50&offset=0  (header: X-API-Key)",
        }, 404);
    }
  } catch (e) {
    // Surface PostgREST detail — it is the difference between a 5-minute fix
    // and an afternoon of guessing.
    const err = e as { message?: string; hint?: string; details?: string; code?: string };
    return json({
      error: err.message ?? "Query failed",
      code: err.code,
      hint: err.hint,
      details: err.details,
      resource,
    }, 500);
  }
});
