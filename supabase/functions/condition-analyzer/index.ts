/**
 * condition-analyzer — interprets machine sound / vibration recordings.
 *
 * The client computes the signal metrics locally (RMS, peak, crest factor,
 * dominant frequencies) and sends them with a short audio sample. This
 * function compares them against the asset's approved baseline and returns a
 * condition verdict the app stores on the recording.
 */
import { handle, gemini, SAFETY_RULE } from '../_shared/guard.ts';

const STATUSES = ['normal', 'watch', 'warning', 'critical'];

Deno.serve(handle({ name: 'condition-analyzer', meterAi: true }, async (ctx) => {
  const b = ctx.body as Record<string, unknown>;
  const recordingType = String(b.recording_type || 'machine_sound');
  const metrics = (b.metrics ?? {}) as Record<string, unknown>;
  const asset = (b.asset ?? {}) as Record<string, unknown>;
  const context = (b.context ?? {}) as Record<string, unknown>;

  // Baseline for this asset + recording type, if one has been approved.
  let baseline: Record<string, unknown> | null = null;
  if (asset.id) {
    const { data } = await ctx.adminClient
      .from('condition_recordings')
      .select('metrics, condition_status, rpm, load_percent, created_at')
      .eq('organization_id', ctx.orgId)
      .eq('asset_id', String(asset.id))
      .eq('recording_type', recordingType)
      .eq('is_baseline', true)
      .is('removed_at', null)
      .maybeSingle();
    baseline = data ?? null;
  }

  // Recent history gives the model a trend rather than a single snapshot.
  const { data: history } = asset.id
    ? await ctx.adminClient
        .from('condition_recordings')
        .select('condition_status, metrics, created_at')
        .eq('organization_id', ctx.orgId)
        .eq('asset_id', String(asset.id))
        .eq('recording_type', recordingType)
        .is('removed_at', null)
        .order('created_at', { ascending: false })
        .limit(6)
    : { data: [] };

  const audio = typeof b.audio_base64 === 'string' && b.audio_base64.length < 6_000_000
    ? { mime_type: String(b.mime_type || 'audio/webm'), data: b.audio_base64 }
    : null;

  const prompt = `You are a rotating-equipment condition monitoring specialist.
Interpret these ${recordingType.replace('_', ' ')} measurements for an industrial machine.
${SAFETY_RULE}

Judge the machine's condition from the supplied metrics, comparing against the
baseline when one is given. Typical faults to consider: unbalance (1x running
speed), misalignment (2x), looseness (multiple harmonics), bearing defect
frequencies and high-frequency noise, cavitation, gear mesh problems,
electrical hum, belt slip.

Be conservative. If the data is insufficient, say so and set confidence Low
rather than inventing a diagnosis.

Return ONLY JSON with keys:
  condition_status (one of ${STATUSES.join(', ')})
  summary          (string, 2-4 sentences in plain language for a technician)
  findings         (array of strings)
  likely_faults    (array of {fault, likelihood, evidence})
  recommended_actions (array of strings, ordered and safe)
  safety           (string)
  confidence       (string: High, Medium or Low)
  trend            (string: improving, stable, worsening or unknown)

ASSET: ${JSON.stringify(asset).slice(0, 4000)}
OPERATING CONTEXT: ${JSON.stringify(context).slice(0, 4000)}
MEASURED METRICS: ${JSON.stringify(metrics).slice(0, 20000)}
APPROVED BASELINE: ${JSON.stringify(baseline).slice(0, 8000)}
RECENT HISTORY: ${JSON.stringify(history ?? []).slice(0, 12000)}`;

  const r = await gemini(prompt, { temperature: 0.15, inline: audio });

  const status = STATUSES.includes(String(r.condition_status))
    ? String(r.condition_status) : 'watch';

  return {
    condition_status: status,
    summary: r.summary ?? 'No interpretation available.',
    findings: Array.isArray(r.findings) ? r.findings : [],
    likely_faults: Array.isArray(r.likely_faults) ? r.likely_faults : [],
    recommended_actions: Array.isArray(r.recommended_actions) ? r.recommended_actions : [],
    safety: r.safety ?? 'Isolate and lock out before any physical inspection.',
    confidence: r.confidence ?? 'Low',
    trend: r.trend ?? 'unknown',
    baseline_compared: !!baseline,
  };
}));
