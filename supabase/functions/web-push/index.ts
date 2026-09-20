/**
 * web-push — device subscription registry and notification delivery.
 *
 * Routes (the path is appended to the function URL by the callers):
 *   POST /subscribe    user JWT   — register this device
 *   POST /unsubscribe  user JWT   — drop this device
 *   POST /test         user JWT   — send the caller a test notification
 *   POST /poll         internal   — deliver queued rows, called by the scheduler
 *
 * /poll is authenticated with X-Internal-Token, compared in constant time.
 * The previous token was committed to this public repository; it is now read
 * from a function secret and must be rotated.
 */
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/guard.ts';
import { sendPush, type PushSubscription } from '../_shared/webpush.ts';

const env = (k: string) => Deno.env.get(k) || '';

/** Length-independent comparison so the token cannot be guessed by timing. */
function safeEqual(a: string, b: string): boolean {
  if (!a || !b) return false;
  const ab = new TextEncoder().encode(a);
  const bb = new TextEncoder().encode(b);
  let diff = ab.length ^ bb.length;
  const n = Math.max(ab.length, bb.length);
  for (let i = 0; i < n; i++) diff |= (ab[i] ?? 0) ^ (bb[i] ?? 0);
  return diff === 0;
}

const BATCH = 200;

Deno.serve(async (req) => {
  const cors = corsHeaders(req.headers.get('origin'));
  const json = (d: unknown, status = 200) =>
    new Response(JSON.stringify(d), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ ok: false, error: 'Method not allowed' }, 405);

  const url = env('SUPABASE_URL');
  const service = env('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !service) return json({ ok: false, error: 'Server misconfigured' }, 500);

  const admin = createClient(url, service, { auth: { persistSession: false } });
  const route = new URL(req.url).pathname.replace(/^.*\/web-push/, '').replace(/\/+$/, '') || '/';
  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { /* empty body is fine */ }

  const vapid = {
    publicKey: env('VAPID_PUBLIC_KEY'),
    privateKey: env('VAPID_PRIVATE_KEY'),
    subject: env('VAPID_SUBJECT') || 'mailto:support@hsbfix.org',
  };

  // ---------------------------------------------------------------- /poll --
  if (route === '/poll') {
    const expected = env('PUSH_INTERNAL_TOKEN');
    const provided = req.headers.get('x-internal-token') || String(body.token || '');
    if (!expected) return json({ ok: false, error: 'Server misconfigured' }, 500);
    if (!safeEqual(expected, provided)) return json({ ok: false, error: 'Forbidden' }, 403);
    if (!vapid.publicKey || !vapid.privateKey) return json({ ok: false, error: 'VAPID keys not configured' }, 500);

    const { data: queued, error } = await admin
      .from('notifications')
      .select('id, organization_id, user_id, title, body, route, severity, category, alarm, entity_type, entity_id')
      .is('pushed_at', null)
      .not('user_id', 'is', null)
      .gt('created_at', new Date(Date.now() - 24 * 3600_000).toISOString())
      .order('created_at', { ascending: true })
      .limit(BATCH);

    if (error) return json({ ok: false, error: error.message }, 500);
    if (!queued?.length) return json({ ok: true, sent: 0, notifications: 0 });

    const userIds = [...new Set(queued.map((n) => n.user_id).filter(Boolean))];
    const { data: subs } = await admin
      .from('push_subscriptions')
      .select('id, user_id, endpoint, p256dh, auth')
      .eq('active', true)
      .in('user_id', userIds);

    const byUser = new Map<string, typeof subs>();
    for (const s of subs ?? []) {
      const list = byUser.get(s.user_id) ?? [];
      list.push(s);
      byUser.set(s.user_id, list);
    }

    let sent = 0, failed = 0;
    const expiredIds: string[] = [];
    const okSubIds: string[] = [];
    const badSubIds: string[] = [];
    const doneIds: string[] = [];

    for (const n of queued) {
      const targets = byUser.get(n.user_id) ?? [];
      for (const s of targets) {
        const result = await sendPush(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } } as PushSubscription,
          {
            title: n.title || 'PlantMaster Pro',
            body: n.body || '',
            url: n.route || '/',
            tag: n.alarm ? `pm-alarm-${n.id}` : `pm-${n.category || 'general'}`,
            data: { id: n.id, severity: n.severity, entity_type: n.entity_type, entity_id: n.entity_id },
          },
          vapid,
          n.alarm ? 3600 : 86400,
        );
        if (result.ok) {
          sent++;
          okSubIds.push(s.id);
        } else {
          failed++;
          if (result.expired) expiredIds.push(s.id);
          else {
            badSubIds.push(s.id);
            console.error('push failed', s.endpoint.slice(0, 60), result.status, result.error);
          }
        }
      }
      doneIds.push(n.id);
    }

    // Mark handled even with no device, otherwise the queue never drains.
    if (doneIds.length) {
      await admin.from('notifications')
        .update({ pushed_at: new Date().toISOString() })
        .in('id', doneIds);
    }
    if (okSubIds.length) {
      await admin.from('push_subscriptions')
        .update({ last_success_at: new Date().toISOString(), failure_count: 0 })
        .in('id', okSubIds);
    }
    // A subscription that keeps failing is parked, not deleted: a transient
    // 500 from the push service must not cost the user their registration.
    if (badSubIds.length) {
      await admin.rpc('bump_push_failures', { p_ids: badSubIds });
    }
    if (expiredIds.length) {
      await admin.from('push_subscriptions').delete().in('id', expiredIds);
    }

    return json({ ok: true, notifications: doneIds.length, sent, failed, pruned: expiredIds.length });
  }

  // -------------------------------------------------- user-authenticated --
  const authHeader = req.headers.get('Authorization') || '';
  if (!authHeader.startsWith('Bearer ')) return json({ ok: false, error: 'Sign in first' }, 401);

  const userClient = createClient(url, env('SUPABASE_ANON_KEY'), {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData } = await userClient.auth.getUser();
  const user = userData?.user;
  if (!user) return json({ ok: false, error: 'Your session has expired' }, 401);

  if (route === '/subscribe') {
    const sub = body.subscription as PushSubscription | undefined;
    if (!sub?.endpoint || !sub.keys?.p256dh || !sub.keys?.auth) {
      return json({ ok: false, error: 'Invalid subscription' }, 400);
    }

    const { data: member } = await admin
      .from('organization_members')
      .select('organization_id')
      .eq('user_id', user.id).eq('active', true)
      .maybeSingle();

    const { error } = await admin.from('push_subscriptions').upsert({
      user_id: user.id,
      organization_id: member?.organization_id ?? null,
      endpoint: sub.endpoint,
      p256dh: sub.keys.p256dh,
      auth: sub.keys.auth,
      user_agent: (req.headers.get('user-agent') || '').slice(0, 300),
      active: true,
      failure_count: 0,
      updated_at: new Date().toISOString(),
    }, { onConflict: 'endpoint' });

    if (error) return json({ ok: false, error: error.message }, 500);
    return json({ ok: true });
  }

  if (route === '/unsubscribe') {
    const endpoint = String((body.subscription as PushSubscription | undefined)?.endpoint || body.endpoint || '');
    if (!endpoint) return json({ ok: false, error: 'endpoint is required' }, 400);
    await admin.from('push_subscriptions').delete().eq('user_id', user.id).eq('endpoint', endpoint);
    return json({ ok: true });
  }

  if (route === '/test') {
    if (!vapid.publicKey || !vapid.privateKey) return json({ ok: false, error: 'VAPID keys not configured' }, 500);
    const { data: subs } = await admin
      .from('push_subscriptions').select('id, endpoint, p256dh, auth')
      .eq('user_id', user.id).eq('active', true);
    if (!subs?.length) return json({ ok: false, error: 'This device is not subscribed' }, 404);

    let sent = 0;
    for (const s of subs) {
      const r = await sendPush(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
        { title: 'PlantMaster Pro', body: 'Alerts are working on this device.', url: '/', tag: 'pm-test' },
        vapid,
      );
      if (r.ok) sent++;
      else if (r.expired) await admin.from('push_subscriptions').delete().eq('id', s.id);
    }
    return json({ ok: sent > 0, sent });
  }

  return json({ ok: false, error: 'Unknown route' }, 404);
});
