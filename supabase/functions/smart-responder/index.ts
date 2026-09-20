/**
 * smart-responder — AI troubleshooting grounded in the tenant's own sources.
 *
 * Hardened over the original: CORS is pinned, the caller must present a valid
 * JWT and belong to the organization, and the monthly AI budget is enforced.
 * Grounding context is fetched server-side with the service key scoped to the
 * verified organization, so the client cannot inject another tenant's manuals.
 */
import { handle, gemini, SAFETY_RULE } from '../_shared/guard.ts';

interface Body {
  organization_id: string;
  plant_id?: string;
  question?: string;
  mode?: string;
  language?: string;
  asset?: Record<string, unknown>;
  context?: Record<string, unknown>;
  offlineReference?: unknown;
}

Deno.serve(handle({ name: 'smart-responder', meterAi: true }, async (ctx) => {
  const body = ctx.body as unknown as Body;
  const question = String(body.question || '').trim();
  if (!question) throw new Error('Ask a question first');
  if (question.length > 4000) throw new Error('That question is too long');

  const mode = String(body.mode || 'quick');
  const language = String(body.language || 'en');
  const term = question.slice(0, 80);

  // ---- grounding, always scoped to the verified organization ---------------
  const admin = ctx.adminClient;
  const [manuals, chunks, experiences, cases] = await Promise.all([
    admin.from('manuals')
      .select('title, manufacturer, model, page_number')
      .eq('organization_id', ctx.orgId).is('removed_at', null)
      .or(`title.ilike.%${term}%,manufacturer.ilike.%${term}%,model.ilike.%${term}%`)
      .limit(10),
    admin.from('document_chunks')
      .select('content, page_number, manuals(title)')
      .eq('organization_id', ctx.orgId)
      .ilike('content', `%${term}%`)
      .limit(12),
    admin.from('technical_experiences')
      .select('problem, symptoms, root_cause, solution, tools, parts')
      .eq('organization_id', ctx.orgId).eq('approved', true)
      .or(`problem.ilike.%${term}%,symptoms.ilike.%${term}%`)
      .limit(8),
    admin.from('problem_cases')
      .select('title, symptoms, actual_cause, verified_solution')
      .eq('organization_id', ctx.orgId)
      .not('verified_solution', 'is', null)
      .limit(8),
  ]);

  const sources = {
    manuals: manuals.data ?? [],
    manual_extracts: (chunks.data ?? []).map((c: Record<string, unknown>) => ({
      title: (c.manuals as { title?: string } | null)?.title ?? 'manual',
      page: c.page_number,
      text: String(c.content || '').slice(0, 1200),
    })),
    approved_experiences: experiences.data ?? [],
    solved_cases: cases.data ?? [],
    asset: body.asset ?? null,
    context: body.context ?? null,
  };

  const grounded = sources.manual_extracts.length > 0
    || sources.approved_experiences.length > 0
    || sources.solved_cases.length > 0;

  const sourceRule = mode === 'manual'
    ? 'Use ONLY the supplied manuals, plant history and approved experiences. ' +
      'If they do not contain the answer, say so plainly rather than guessing.'
    : mode === 'deep' || mode === 'combined_deep'
    ? 'Use the supplied plant sources first, then reputable general engineering ' +
      'knowledge. Label clearly which parts come from the plant\'s own documents ' +
      'and which are general knowledge.'
    : 'Give a short, practical answer from the supplied plant context and safe ' +
      'general engineering knowledge.';

  const languageRule = language && !language.startsWith('en')
    ? `Reply in ${language}. Keep equipment names, part numbers and units in English.`
    : 'Reply in clear, simple English suitable for a plant technician.';

  const prompt = `You are PlantMaster, an industrial maintenance decision-support assistant.
${sourceRule}
${languageRule}
${SAFETY_RULE}

Rank the likely causes, then give safe checks in order, the measurements to take,
tools needed, likely spare parts, whether a shutdown is required, and when to escalate.

Return ONLY JSON with these keys:
  answer      (string, may use short markdown lists)
  safety      (string, the safety precautions that apply before starting)
  confidence  (string: "High", "Medium" or "Low")
  sources     (array of strings naming what you relied on)

QUESTION:
${question}

PLANT SOURCES (JSON):
${JSON.stringify(sources).slice(0, 120_000)}`;

  const result = await gemini(prompt, {
    temperature: mode.includes('deep') ? 0.25 : 0.15,
    search: mode.includes('deep'),
  });

  return {
    answer: result.answer ?? 'No answer could be generated.',
    safety: result.safety
      ?? 'Follow plant safety procedures, isolation and qualified-person requirements.',
    confidence: result.confidence ?? (grounded ? 'Medium' : 'Low'),
    sources: Array.isArray(result.sources) ? result.sources : [],
    grounded,
  };
}));
