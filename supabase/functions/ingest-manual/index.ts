/**
 * ingest-manual — turns an uploaded manual into searchable chunks.
 *
 * The app uploads the file to storage, inserts the `manuals` row, then calls
 * this. It downloads the object with the service key, asks Gemini to read it
 * page by page, and writes `document_chunks` rows that smart-responder later
 * quotes. Progress is written back to the manual row so the UI can show it.
 *
 * Re-entrant: if the same manual is submitted twice the second call is a
 * no-op unless `force` is set, so a user double-tapping "Index" cannot
 * duplicate every chunk and double the tenant's AI spend.
 */
import { handle, gemini, HttpError } from '../_shared/guard.ts';

const MAX_BYTES = 40 * 1024 * 1024;
const CHUNK_CHARS = 2400;
const CHUNK_OVERLAP = 240;

/** Splits on paragraph boundaries, keeping a little overlap for context. */
function splitText(text: string): string[] {
  const clean = text.replace(/\r/g, '').replace(/\n{3,}/g, '\n\n').trim();
  if (!clean) return [];
  const out: string[] = [];
  let i = 0;
  while (i < clean.length) {
    let end = Math.min(i + CHUNK_CHARS, clean.length);
    if (end < clean.length) {
      const brk = clean.lastIndexOf('\n\n', end);
      if (brk > i + CHUNK_CHARS * 0.5) end = brk;
    }
    const piece = clean.slice(i, end).trim();
    if (piece) out.push(piece);
    if (end >= clean.length) break;
    i = Math.max(end - CHUNK_OVERLAP, i + 1);
  }
  return out;
}

async function setStatus(
  admin: ReturnType<typeof Object>,
  orgId: string,
  manualId: string,
  patch: Record<string, unknown>,
) {
  // deno-lint-ignore no-explicit-any
  await (admin as any).from('manuals').update(patch)
    .eq('id', manualId).eq('organization_id', orgId);
}

Deno.serve(handle({ name: 'ingest-manual', meterAi: true }, async (ctx) => {
  const b = ctx.body as Record<string, unknown>;
  const manualId = String(b.manual_id || '');
  const force = b.force === true;
  if (!manualId) throw new HttpError(400, 'manual_id is required');

  const admin = ctx.adminClient;

  const { data: manual } = await admin
    .from('manuals')
    .select('id, organization_id, plant_id, title, storage_path, mime_type, size_bytes, status')
    .eq('id', manualId)
    .maybeSingle();

  if (!manual) throw new HttpError(404, 'Manual not found');
  if (manual.organization_id !== ctx.orgId) throw new HttpError(404, 'Manual not found');
  if (!manual.storage_path) throw new HttpError(400, 'That manual has no stored file');

  if (manual.status === 'indexing' && !force) {
    return { ok: true, status: 'indexing', message: 'Already being indexed.' };
  }
  if (manual.status === 'indexed' && !force) {
    const { count } = await admin
      .from('document_chunks')
      .select('id', { count: 'exact', head: true })
      .eq('manual_id', manualId);
    if ((count ?? 0) > 0) {
      return { ok: true, status: 'indexed', chunks: count, message: 'Already indexed.' };
    }
  }

  if ((manual.size_bytes ?? 0) > MAX_BYTES) {
    throw new HttpError(413, 'That file is too large to index (limit 40 MB)');
  }

  await setStatus(admin, ctx.orgId, manualId, {
    status: 'indexing',
    index_error: null,
    indexed_at: null,
  });

  try {
    const { data: file, error: dlErr } = await admin.storage
      .from('plant-files')
      .download(manual.storage_path);
    if (dlErr || !file) throw new HttpError(404, 'The stored file could not be read');

    const bytes = new Uint8Array(await file.arrayBuffer());
    if (bytes.byteLength > MAX_BYTES) {
      throw new HttpError(413, 'That file is too large to index (limit 40 MB)');
    }

    // Base64 without blowing the stack on large files.
    let binary = '';
    const STEP = 0x8000;
    for (let i = 0; i < bytes.length; i += STEP) {
      binary += String.fromCharCode(...bytes.subarray(i, i + STEP));
    }
    const base64 = btoa(binary);

    const mime = String(manual.mime_type || 'application/pdf');
    const prompt = `Transcribe this technical manual for a maintenance knowledge base.

Preserve the reading order, headings, tables (as readable text), part numbers,
torque values, tolerances, set points and units exactly as printed. Skip page
furniture such as repeated headers, footers and page numbers.

Return ONLY JSON:
{
  "pages": [ { "page": 1, "heading": "short section title or empty", "text": "full text of the page" } ],
  "document_title": "the manual's own title if printed",
  "manufacturer": "if printed, else empty",
  "model": "if printed, else empty",
  "language": "ISO code of the document language"
}`;

    const parsed = await gemini(prompt, {
      temperature: 0,
      inline: { mime_type: mime, data: base64 },
    });

    const pages = Array.isArray(parsed.pages) ? parsed.pages : [];
    if (!pages.length) throw new HttpError(422, 'No readable text was found in that file');

    const rows: Record<string, unknown>[] = [];
    let index = 0;
    for (const p of pages as Record<string, unknown>[]) {
      const pageNo = Number(p.page) || rows.length + 1;
      const heading = String(p.heading || '').slice(0, 300);
      for (const piece of splitText(String(p.text || ''))) {
        rows.push({
          organization_id: ctx.orgId,
          manual_id: manualId,
          chunk_index: index++,
          page_number: pageNo,
          heading,
          content: piece,
        });
      }
    }
    if (!rows.length) throw new HttpError(422, 'No readable text was found in that file');

    // Replace any previous index atomically enough for our purposes.
    await admin.from('document_chunks').delete()
      .eq('organization_id', ctx.orgId).eq('manual_id', manualId);

    for (let i = 0; i < rows.length; i += 200) {
      const { error } = await admin.from('document_chunks').insert(rows.slice(i, i + 200));
      if (error) throw new HttpError(500, `Indexing failed: ${error.message}`);
    }

    const patch: Record<string, unknown> = {
      status: 'indexed',
      indexed_at: new Date().toISOString(),
      chunk_count: rows.length,
      page_count: pages.length,
      index_error: null,
    };
    if (parsed.manufacturer) patch.manufacturer = String(parsed.manufacturer).slice(0, 200);
    if (parsed.model) patch.model = String(parsed.model).slice(0, 200);
    await setStatus(admin, ctx.orgId, manualId, patch);

    await admin.from('audit_logs').insert({
      organization_id: ctx.orgId,
      plant_id: manual.plant_id,
      user_id: ctx.userId,
      action: 'manual_indexed',
      entity_type: 'manual',
      entity_id: manualId,
      details: { chunks: rows.length, pages: pages.length, title: manual.title },
    });

    return { ok: true, status: 'indexed', chunks: rows.length, pages: pages.length };

  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    await setStatus(admin, ctx.orgId, manualId, {
      status: 'failed',
      index_error: message.slice(0, 500),
    });
    throw err;
  }
}));
