/**
 * Shared guard for every PlantMaster edge function.
 *
 * The original smart-responder shipped with `Access-Control-Allow-Origin: *`
 * and no authentication at all: anyone on the internet could POST to it and
 * spend the project's Gemini quota. Every function now goes through
 * `handle()`, which pins CORS to known origins, requires a valid Supabase
 * JWT, confirms the caller really belongs to the organization they claim,
 * enforces the plan's monthly AI budget and records usage.
 */
import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';

const ALLOWED_ORIGINS = [
  'https://app.hsbfix.org',
  'https://admin.hsbfix.org',
  'https://hsbfix.org',
  'https://www.hsbfix.org',
  'http://localhost:8080',
  'http://localhost:8082',
];

export function corsHeaders(origin: string | null): Record<string, string> {
  const allowed = origin && ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    'Access-Control-Allow-Origin': allowed,
    'Access-Control-Allow-Headers':
      'authorization, x-client-info, apikey, content-type, x-internal-token',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin',
  };
}

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export interface Ctx {
  req: Request;
  body: Record<string, unknown>;
  userId: string;
  orgId: string;
  /** Acts as the calling user: RLS applies, so it cannot read another tenant. */
  userClient: SupabaseClient;
  /** Bypasses RLS. Use only for writes the user is not allowed to make directly. */
  adminClient: SupabaseClient;
  json: (data: unknown, status?: number) => Response;
}

const env = (k: string): string => {
  const v = Deno.env.get(k);
  if (!v) throw new HttpError(500, `Server misconfigured: ${k} is not set`);
  return v;
};

/** Monthly AI budget from the tenant's plan. */
async function enforceAiQuota(admin: SupabaseClient, orgId: string) {
  const { data: org } = await admin
    .from('organizations')
    .select('plan_code, commercial_status')
    .eq('id', orgId).maybeSingle();

  if (!org) throw new HttpError(404, 'Workspace not found');
  if (['suspended', 'cancelled'].includes(org.commercial_status)) {
    throw new HttpError(403, `This workspace is ${org.commercial_status}.`);
  }

  const { data: plan } = await admin
    .from('subscription_plans')
    .select('ai_requests_month')
    .eq('code', org.plan_code).maybeSingle();

  const limit = plan?.ai_requests_month ?? 0;
  if (limit <= 0) {
    throw new HttpError(403, 'AI features are not included in your current plan.');
  }

  const monthStart = new Date();
  monthStart.setUTCDate(1);
  monthStart.setUTCHours(0, 0, 0, 0);

  const { count } = await admin
    .from('ai_usage_events')
    .select('id', { count: 'exact', head: true })
    .eq('organization_id', orgId)
    .gte('created_at', monthStart.toISOString());

  if ((count ?? 0) >= limit) {
    throw new HttpError(429,
      `Monthly AI limit reached (${limit} requests). It resets next month, or upgrade the plan.`);
  }
}

export interface Options {
  /** Require the caller to be a member of body.organization_id. Default true. */
  requireOrg?: boolean;
  /** Check and record AI usage against the plan. Default false. */
  meterAi?: boolean;
  /** Function name recorded in ai_usage_events. */
  name: string;
}

export function handle(opts: Options, fn: (ctx: Ctx) => Promise<unknown>) {
  return async (req: Request): Promise<Response> => {
    const cors = corsHeaders(req.headers.get('origin'));
    const json = (data: unknown, status = 200) =>
      new Response(JSON.stringify(data), {
        status,
        headers: { ...cors, 'Content-Type': 'application/json' },
      });

    if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
    if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

    const started = Date.now();
    let orgId = '';
    let userId = '';
    let admin: SupabaseClient | null = null;

    try {
      const url = env('SUPABASE_URL');
      const anon = env('SUPABASE_ANON_KEY');
      const service = env('SUPABASE_SERVICE_ROLE_KEY');

      const authHeader = req.headers.get('Authorization') || '';
      if (!authHeader.startsWith('Bearer ')) {
        throw new HttpError(401, 'Sign in to use this feature');
      }

      const userClient = createClient(url, anon, {
        global: { headers: { Authorization: authHeader } },
        auth: { persistSession: false },
      });
      admin = createClient(url, service, { auth: { persistSession: false } });

      const { data: userData, error: userErr } = await userClient.auth.getUser();
      if (userErr || !userData?.user) throw new HttpError(401, 'Your session has expired');
      userId = userData.user.id;

      let body: Record<string, unknown> = {};
      try { body = await req.json(); } catch { body = {}; }

      if (opts.requireOrg !== false) {
        orgId = String(body.organization_id || '');
        if (!orgId) throw new HttpError(400, 'organization_id is required');

        // Membership is checked against the database, never trusted from the body.
        const { data: member } = await admin
          .from('organization_members')
          .select('role')
          .eq('organization_id', orgId)
          .eq('user_id', userId)
          .eq('active', true)
          .maybeSingle();

        if (!member) throw new HttpError(403, 'You are not a member of this workspace');
        if (member.role === 'viewer') {
          throw new HttpError(403, 'Read-only demo — this action is disabled.');
        }
      }

      if (opts.meterAi) await enforceAiQuota(admin, orgId);

      const result = await fn({ req, body, userId, orgId, userClient, adminClient: admin, json });

      if (opts.meterAi && admin) {
        try {
          await admin.from('ai_usage_events').insert({
            organization_id: orgId, user_id: userId,
            function_name: opts.name, mode: String(body.mode || ''), success: true,
          });
        } catch (e) { console.error('usage log failed', e); }
      }
      return result instanceof Response ? result : json(result);

    } catch (error) {
      const status = error instanceof HttpError ? error.status : 500;
      const message = error instanceof Error ? error.message : String(error);

      if (opts.meterAi && admin && orgId && status !== 429 && status !== 403) {
        try {
          await admin.from('ai_usage_events').insert({
            organization_id: orgId, user_id: userId,
            function_name: opts.name, success: false,
          });
        } catch { /* never mask the original error */ }
      }
      // Never leak internals to the browser.
      console.error(`[${opts.name}] ${status} ${message} (${Date.now() - started}ms)`);
      return json({ error: status >= 500 ? 'The service had a problem. Try again.' : message }, status);
    }
  };
}

/** Calls Gemini and returns parsed JSON, tolerating a non-JSON reply. */
export async function gemini(
  prompt: string,
  {
    model = 'gemini-2.5-flash',
    temperature = 0.15,
    search = false,
    inline = null as { mime_type: string; data: string } | null,
    extraInline = [] as { mime_type: string; data: string }[],
  } = {},
): Promise<Record<string, unknown>> {
  const key = env('GEMINI_API_KEY');

  const parts: Record<string, unknown>[] = [{ text: prompt }];
  if (inline) parts.push({ inline_data: { mime_type: inline.mime_type, data: inline.data } });
  for (const extra of extraInline) {
    parts.push({ inline_data: { mime_type: extra.mime_type, data: extra.data } });
  }

  const payload: Record<string, unknown> = {
    contents: [{ role: 'user', parts }],
    generationConfig: { temperature, responseMimeType: search ? 'text/plain' : 'application/json' },
    safetySettings: [
      { category: 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold: 'BLOCK_ONLY_HIGH' },
    ],
  };
  if (search) payload.tools = [{ google_search: {} }];

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 55_000);
  try {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${encodeURIComponent(key)}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
        signal: controller.signal,
      },
    );
    const raw = await res.text();
    if (!res.ok) {
      console.error('gemini error', res.status, raw.slice(0, 500));
      throw new HttpError(res.status === 429 ? 429 : 502,
        res.status === 429 ? 'AI service is busy. Try again shortly.' : 'AI service error');
    }
    const parsed = JSON.parse(raw);
    const text = parsed.candidates?.[0]?.content?.parts
      ?.map((p: { text?: string }) => p.text || '').join('') || '';
    try {
      return JSON.parse(text.replace(/^```(?:json)?\s*|\s*```$/g, ''));
    } catch {
      return { answer: text };
    }
  } finally {
    clearTimeout(timer);
  }
}

export const SAFETY_RULE =
  'Never advise bypassing guards, interlocks, emergency stops, lock-out/tag-out, ' +
  'pressure isolation or qualified-person requirements. If an action is unsafe ' +
  'without isolation, say so first and require isolation.';
