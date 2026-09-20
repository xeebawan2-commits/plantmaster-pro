import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// PlantMaster Pro — ingest-manual (v5: FAST)
// - PDFs up to 4 MB: sent INLINE to Gemini (no file-upload wait) — small manuals index in ~20-40 s
// - Larger PDFs: official 2-step resumable upload + resume + bounded "still processing" waits
// - Bigger page batches (25 pages) run 2 at a time in parallel
// Called from the app with a user JWT (auto-runs after upload; button = full re-index).
// Owner/manager only. Verify JWT: ON.

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization,x-client-info,apikey,content-type" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

function toB64(bytes: Uint8Array): string {
  let bin = "";
  const CH = 0x8000;
  for (let i = 0; i < bytes.length; i += CH) bin += String.fromCharCode(...bytes.subarray(i, i + CH));
  return btoa(bin);
}

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

const MAX_PAGES = 150;      // bigger PDFs: split into parts first
const BATCH_PAGES = 50;     // pages per Gemini extraction call (fewer calls = cheaper: the whole doc is billed per call; 150 pages = 3 reads)
const PARALLEL = 2;         // batches running at once
const INLINE_MAX = 12 * 1024 * 1024; // <=12 MB goes inline (fast path; keeps under Gemini 20 MB request limit)
const DEADLINE_MS = 130000; // stay under the platform's function time limit

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const started = Date.now();
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
    const admin = createClient(url, secret, { auth: { persistSession: false, autoRefreshToken: false } });

    const input = await req.json();
    const orgId = String(input.organization_id || "");
    const manualId = String(input.manual_id || "");
    const force = Boolean(input.force); // true = full re-index, false = resume
    if (!orgId || !manualId) return json({ error: "organization_id and manual_id are required" }, 400);

    const member = await userClient.from("organization_members").select("role").eq("organization_id", orgId).eq("user_id", user.id).eq("active", true).maybeSingle();
    if (member.error || !member.data) return json({ error: "Active company membership required" }, 403);
    if (!["owner", "manager"].includes(String(member.data.role))) return json({ error: "Owner or manager permission required to index manuals" }, 403);

    const mres = await admin.from("manuals").select("id,title,mime_type,size_bytes,storage_path,status").eq("id", manualId).eq("organization_id", orgId).maybeSingle();
    if (mres.error || !mres.data) return json({ error: "Manual not found" }, 404);
    const manual = mres.data as any;
    if (String(manual.mime_type) !== "application/pdf") return json({ error: "AI indexing works on PDF files only (this file: " + String(manual.mime_type) + ")" }, 400);
    if ((manual.size_bytes || 0) > 20 * 1024 * 1024) return json({ error: "Manual is over 20 MB — split it into smaller PDFs first" }, 400);

    // ---- resume support: which pages already have chunks? ----
    const ex = await admin.from("document_chunks").select("page_number").eq("manual_id", manualId).not("page_number", "is", null);
    const covered = new Set<number>((ex.data || []).map((r: any) => Number(r.page_number)));
    if (force) {
      await admin.from("document_chunks").delete().eq("manual_id", manualId);
      covered.clear();
    }

    const { data: fileData, error: fe } = await admin.storage.from("plant-files").download(manual.storage_path);
    if (fe || !fileData) return json({ error: "Could not read the manual file from storage" }, 500);
    const fileBytes = new Uint8Array(await fileData.arrayBuffer());

    // ---- 1) attach the PDF: INLINE (fast, <=4 MB) or resumable upload (bigger) ----
    let filePart: any;
    let uploadedFileId = "";
    if (fileBytes.length <= INLINE_MAX) {
      filePart = { inline_data: { mime_type: "application/pdf", data: toB64(fileBytes) } };
    } else {
      // reuse a file we already uploaded for this manual (retries must NOT re-upload:
      // a fresh upload makes Gemini restart processing the big PDF from zero)
      const marker = "pm-" + manualId;
      let existing: { id: string; uri: string; state: string } | null = null;
      try {
        const lst: any = await fetch(`https://generativelanguage.googleapis.com/v1beta/files?pageSize=50&key=${encodeURIComponent(key)}`).then((r) => r.json().catch(() => ({})));
        for (const f of lst.files || []) {
          if (String(f.display_name || "") === marker && /ACTIVE|PROCESSING/.test(String(f.state || ""))) {
            existing = { id: String(f.name || "").split("/").pop() || "", uri: String(f.uri || ""), state: String(f.state || "") };
            break;
          }
        }
      } catch (_) {}
      if (existing && !existing.id) existing = null;
      let fileUri = "";
      if (existing) {
        uploadedFileId = existing.id;
        fileUri = existing.uri;
      } else {
        const startRes = await fetch(`https://generativelanguage.googleapis.com/upload/v1beta/files?key=${encodeURIComponent(key)}`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Upload-Protocol": "resumable",
          "X-Goog-Upload-Command": "start",
          "X-Goog-Upload-Header-Content-Length": String(fileBytes.length),
          "X-Goog-Upload-Header-Content-Type": "application/pdf"
        },
        body: JSON.stringify({ file: { display_name: "pm-" + manualId } })
      });
        const uploadUrl = startRes.headers.get("x-goog-upload-url") || "";
        if (!startRes.ok || !uploadUrl) {
          const t = await startRes.text().catch(() => "");
          let m = ""; try { m = String(JSON.parse(t).error?.message || ""); } catch (_) {}
          return json({ error: "Gemini upload start failed: " + (m || t.slice(0, 200) || startRes.status) }, 502);
        }
        const up = await fetch(uploadUrl, {
          method: "POST",
          headers: { "X-Goog-Upload-Offset": "0", "X-Goog-Upload-Command": "upload, finalize" },
          body: fileBytes
        });
        const upText = await up.text();
        let upJson: any = {};
        try { upJson = JSON.parse(upText); } catch (_) {}
        fileUri = String(upJson.file?.uri || "");
        uploadedFileId = String(upJson.file?.name || "").split("/").pop() || "";
        if (!up.ok || !uploadedFileId) return json({ error: "Gemini file upload failed: " + (String(upJson.error?.message || "") || upText.slice(0, 300) || up.status) }, 502);
      }
      // wait until ACTIVE (check-first; a reused file is often already ACTIVE)
      let fileState = "";
      for (let w = 0; w < 20 && !/ACTIVE/.test(fileState); w++) {
        const st: any = await fetch(`https://generativelanguage.googleapis.com/v1beta/files/${uploadedFileId}?key=${encodeURIComponent(key)}`).then((r) => r.json().catch(() => ({})));
        fileState = String(st.file?.state || "");
        if (/FAILED/.test(fileState)) return json({ error: "Gemini could not process this PDF (it may be password-protected or corrupted)" }, 502);
        if (/ACTIVE/.test(fileState)) break;
        await new Promise((r) => setTimeout(r, 5000));
      }
      if (!/ACTIVE/.test(fileState)) return json({ ok: false, retry: true, message: "Gemini is still processing the large file — retrying automatically (file is being kept, no re-upload)" });
      filePart = { file_data: { mime_type: "application/pdf", file_uri: fileUri || `https://generativelanguage.googleapis.com/v1beta/files/${uploadedFileId}` } };
    }

    if (Date.now() - started > 100000) return json({ ok: false, retry: true, message: "Running low on time — retrying automatically" });

    const model = "gemini-3.1-flash-lite";
    const ask = async (prompt: string, maxOut: number) => {
      const g = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${encodeURIComponent(key)}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ role: "user", parts: [{ text: prompt }, filePart] }],
          generationConfig: { temperature: 0, maxOutputTokens: maxOut }
        })
      });
      const gj: any = await g.json().catch(() => ({}));
      const text = gj.candidates?.[0]?.content?.parts?.map((x: any) => x.text || "").join("") || "";
      if (!g.ok && !text) throw Error(`Gemini extraction failed: ${String(gj.error?.message || g.status)}`);
      return text;
    };

    // ---- 2) extract text in page batches (2 in parallel), saving each batch as it completes ----
    // The FIRST batch also reports the total page count, so we never pay for a
    // separate full-document read just to count pages.
    let totalChunks = 0;
    let batchesRun = 0;
    let totalPages = 0;
    let countFetched = false;
    let pending: { from: number; to: number }[] = [{ from: 1, to: BATCH_PAGES }];
    const scheduleRest = (after: number) => {
      if (totalPages > MAX_PAGES) return;
      for (let f = after + 1; f <= totalPages; f += BATCH_PAGES) pending.push({ from: f, to: Math.min(f + BATCH_PAGES - 1, totalPages) });
    };
    while (pending.length) {
      const group = pending.splice(0, PARALLEL).filter(r => {
        // resume: skip page ranges that already have chunks
        for (let p = r.from; p <= r.to; p++) if (!covered.has(p)) return true;
        return false;
      });
      if (!group.length) continue;
      if (Date.now() - started > DEADLINE_MS) return json({ ok: false, retry: true, message: "Time limit reached — progress saved, retrying automatically" });
      const results = await Promise.all(group.map(async (r) => {
        const isCountCall = !countFetched && r.from === 1;
        const text0 = await ask(
          isCountCall
            ? `First reply with exactly one line: TOTAL_PAGES=<total number of pages in this document>. Then extract the exact text of pages ${r.from} to ${r.to} of this technical manual. For EACH page output exactly this marker line first: [PAGE n]  (n is the page number), then that page's text. Keep table rows as plain text. Skip empty pages. No commentary.`
            : `Extract the exact text of pages ${r.from} to ${r.to} of this technical manual. For EACH page output exactly this marker line first: [PAGE n]  (n is the page number), then that page's text. Keep table rows as plain text. Skip empty pages. No commentary.`,
          32768
        );
        let text = text0;
        if (isCountCall) {
          const m = /TOTAL_PAGES\s*[=:]\s*(\d+)/i.exec(text0);
          if (m) { totalPages = parseInt(m[1], 10) || 0; countFetched = true; scheduleRest(r.to); }
          text = text0.replace(/^\s*TOTAL_PAGES\s*[=:]\s*\d+\s*\n?/i, "");
        }
        if (totalPages > MAX_PAGES) throw Error(`Manual has about ${totalPages} pages (max ${MAX_PAGES}). Split it into smaller PDFs and index each part.`);
        const rows: { manual_id: string; page_number: number | null; content: string }[] = [];
        const pageMarker = /^\[PAGE\s*(\d+)\]/i;
        let curPage: number | null = null;
        let buf = "";
        const flush = () => {
          const t = buf.trim();
          if (t) for (let j = 0; j < t.length; j += 700) rows.push({ manual_id: manualId, page_number: curPage, content: t.slice(j, j + 700) });
          buf = "";
        };
        for (const line of text.split("\n")) {
          const m = pageMarker.exec(line.trim());
          if (m) { flush(); curPage = parseInt(m[1], 10) || null; }
          else buf += line + "\n";
        }
        flush();
        if (!rows.length && text.trim()) rows.push({ manual_id: manualId, page_number: r.from, content: text.trim().slice(0, 4000) });
        return rows;
      }));
      for (const rows of results) {
        if (rows.length) {
          const ins = await admin.from("document_chunks").insert(rows);
          if (ins.error) throw Error("Saving chunks failed: " + ins.error.message);
          totalChunks += rows.length;
        }
        batchesRun++;
      }
      if (!countFetched) {
        // first batch did not report the total — one fallback count call
        const countText = await ask("How many pages does this PDF document have? Reply with ONLY the number.", 20);
        totalPages = parseInt(countText.replace(/\D/g, ""), 10) || 1;
        countFetched = true;
        scheduleRest(BATCH_PAGES);
      }
    }
    if (!totalPages) totalPages = 1;

    // ---- 4) done ----
    await admin.from("manuals").update({ status: "indexed" }).eq("id", manualId);
    if (uploadedFileId) await fetch(`https://generativelanguage.googleapis.com/v1beta/files/${uploadedFileId}?key=${encodeURIComponent(key)}`, { method: "DELETE" }).catch(() => {});
    return json({ ok: true, pages: totalPages, chunks: totalChunks, batches: batchesRun, resumed: covered.size > 0 && !force, inline: fileBytes.length <= INLINE_MAX, model, ms: Date.now() - started });
  } catch (e) {
    return json({ error: String((e as any)?.message || e) }, 500);
  }
});

