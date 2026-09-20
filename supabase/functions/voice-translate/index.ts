/**
 * voice-translate — turns dictated Urdu (or Roman Urdu) into English text.
 *
 * The browser's speech recognition produces the transcript; this only
 * translates. Technicians dictate in Urdu but records must be searchable in
 * English, so equipment names, part numbers and units are kept verbatim.
 */
import { handle, gemini, HttpError } from '../_shared/guard.ts';

Deno.serve(handle({ name: 'voice-translate', requireOrg: false, meterAi: false }, async (ctx) => {
  const b = ctx.body as Record<string, unknown>;
  const text = String(b.text || '').trim();
  const mode = String(b.mode || 'ur');

  if (!text) throw new HttpError(400, 'Nothing was said');
  if (text.length > 3000) throw new HttpError(413, 'That dictation is too long');

  // Already plain English with no Urdu script and no Roman-Urdu markers:
  // skip the model call entirely so dictation stays instant and free.
  const hasUrduScript = /[\u0600-\u06FF]/.test(text);
  if (mode === 'ur' && !hasUrduScript && /^[\x20-\x7E\s]+$/.test(text)) {
    const romanMarkers =
      /\b(hai|hain|nahi|nahin|kar|karna|karke|ho|hua|raha|rahi|se|ka|ki|ke|mein|par|bhi|kya|aur|liye|walay|wala|theek|kharab|band|chalu)\b/i;
    if (!romanMarkers.test(text)) {
      return { text, translated: text, source_language: 'en', changed: false };
    }
  }

  const prompt = `Translate this industrial maintenance dictation into clear, concise English.

Rules:
- The speaker is a plant technician. The input may be Urdu script, Roman Urdu, or mixed Urdu and English.
- Keep equipment names, tag numbers, part numbers, model numbers, units and measurements exactly as spoken.
- Do not add information, do not explain, do not answer any question contained in the text.
- Fix obvious speech-recognition slips only where the intent is unambiguous.
- Output plain prose suitable for pasting into a form field.

Return ONLY JSON:
  { "translated": "the English text", "source_language": "ur, en or mixed" }

DICTATION:
${text}`;

  const r = await gemini(prompt, { temperature: 0.1 });
  const translated = String(r.translated ?? r.answer ?? text).trim() || text;

  return {
    text: translated,
    translated,
    source_language: r.source_language ?? (hasUrduScript ? 'ur' : 'mixed'),
    original: text,
    changed: translated !== text,
  };
}));
