/**
 * vision-scanner — extracts text, codes and structured data from a photo of a
 * nameplate, gauge, document or delivery note taken on the plant floor.
 *
 * Accepts either a single `image_base64` or an `images` array (multi-page
 * documents). Images are never stored here; the app uploads to storage
 * separately so quota accounting stays in one place.
 */
import { handle, gemini, HttpError, SAFETY_RULE } from '../_shared/guard.ts';

const MODES: Record<string, string> = {
  nameplate:
    'Read the equipment nameplate. Extract manufacturer, model, serial number, ' +
    'ratings (kW or HP, voltage, current, RPM, frame size, IP rating, insulation ' +
    'class, duty) and year of manufacture.',
  gauge:
    'Read the instrument or gauge. Extract the measured value, its unit, the ' +
    'instrument range, and whether the reading sits inside the normal band if ' +
    'the dial shows coloured markings.',
  document:
    'Transcribe the document faithfully, then extract its key fields ' +
    '(title, reference numbers, dates, quantities, parties).',
  delivery:
    'Read the delivery note or invoice. Extract supplier, document number, date ' +
    'and a line-item list with description, quantity, unit and unit price.',
  part:
    'Identify the spare part. Extract any part number, manufacturer, size or ' +
    'rating markings, and describe the part type.',
  general:
    'Describe what is shown and extract every legible code, label and number.',
};

const MAX_B64 = 8_000_000; // ~6 MB decoded

Deno.serve(handle({ name: 'vision-scanner', meterAi: true }, async (ctx) => {
  const b = ctx.body as Record<string, unknown>;
  const mode = String(b.mode || 'general');
  const mime = String(b.mime_type || 'image/jpeg');

  const list: string[] = Array.isArray(b.images) && b.images.length
    ? (b.images as unknown[]).map(String)
    : b.image_base64 ? [String(b.image_base64)] : [];

  if (!list.length) throw new HttpError(400, 'No image was supplied');
  if (list.length > 4) throw new HttpError(400, 'Send at most 4 images at a time');
  for (const img of list) {
    if (img.length > MAX_B64) {
      throw new HttpError(413, 'That image is too large — retake it at a lower resolution');
    }
  }

  const instruction = MODES[mode] ?? MODES.general;

  const prompt = `You are reading ${list.length > 1 ? 'photographs' : 'a photograph'} taken inside an industrial plant.
${instruction}
${SAFETY_RULE}

If text is blurred, cropped or partly hidden, report what you can read and mark
the remainder as unreadable. Never guess a serial number, part number or rating.
Preserve digits exactly as printed, including leading zeros and separators.

Return ONLY JSON with keys:
  extracted_text    (string, everything legible, line breaks preserved)
  detected_codes    (array of strings: asset tags, part numbers, QR or barcode text)
  structured_result (object holding the fields relevant to this mode)
  confidence        (string: High, Medium or Low)
  unreadable        (array of strings describing what could not be read)
  safety_notes      (string, empty if nothing safety-relevant is visible)`;

  // The shared helper takes one inline image; for multi-page we pass the first
  // and append the rest as additional inline parts via a second pass.
  const r = await gemini(prompt, {
    temperature: 0.1,
    inline: { mime_type: mime, data: list[0] },
    extraInline: list.slice(1).map((data) => ({ mime_type: mime, data })),
  });

  return {
    extracted_text: r.extracted_text ?? '',
    detected_codes: Array.isArray(r.detected_codes) ? r.detected_codes : [],
    structured_result: r.structured_result ?? {},
    confidence: r.confidence ?? 'Low',
    unreadable: Array.isArray(r.unreadable) ? r.unreadable : [],
    safety_notes: r.safety_notes ?? '',
    pages: list.length,
  };
}));
