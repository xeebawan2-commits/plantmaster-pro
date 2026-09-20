/**
 * daily-reports — emails each company its maintenance summary.
 *
 * Route: POST /run with the shared token (called every day by the scheduler).
 *
 * The scheduler fires once a day at a fixed UTC time, but each company sets
 * its own `report_time` in its own timezone, so this checks which companies
 * are due right now rather than blindly mailing everyone. A run is recorded in
 * `daily_report_runs`, which makes the endpoint idempotent: re-running it (or
 * a duplicate scheduler fire) will not send the same report twice.
 */
import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';

const env = (k: string) => Deno.env.get(k) || '';

function safeEqual(a: string, b: string): boolean {
  if (!a || !b) return false;
  const ab = new TextEncoder().encode(a);
  const bb = new TextEncoder().encode(b);
  let diff = ab.length ^ bb.length;
  for (let i = 0; i < Math.max(ab.length, bb.length); i++) diff |= (ab[i] ?? 0) ^ (bb[i] ?? 0);
  return diff === 0;
}

/** Local wall-clock date and minutes-since-midnight for a timezone. */
function localNow(timeZone: string): { date: string; minutes: number } {
  try {
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone, year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', hour12: false,
    }).formatToParts(new Date());
    const get = (t: string) => parts.find((p) => p.type === t)?.value ?? '00';
    return {
      date: `${get('year')}-${get('month')}-${get('day')}`,
      minutes: Number(get('hour')) * 60 + Number(get('minute')),
    };
  } catch {
    const d = new Date();
    return { date: d.toISOString().slice(0, 10), minutes: d.getUTCHours() * 60 + d.getUTCMinutes() };
  }
}

const esc = (s: unknown) =>
  String(s ?? '').replace(/[&<>"]/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c] as string));

interface Summary {
  woOpen: number; woClosed: number; woOverdue: number;
  logs: number; alarms: number; present: number;
  critical: { title: string; status: string; due: string | null }[];
}

async function buildSummary(
  admin: SupabaseClient, orgId: string, day: string,
): Promise<Summary> {
  const dayStart = `${day}T00:00:00`;
  const dayEnd = `${day}T23:59:59`;
  const nowIso = new Date().toISOString();

  const [open, closed, overdue, logs, alarms, attend, critical] = await Promise.all([
    admin.from('work_orders').select('id', { count: 'exact', head: true })
      .eq('organization_id', orgId).is('removed_at', null)
      .in('status', ['open', 'in_progress', 'on_hold']),
    admin.from('work_orders').select('id', { count: 'exact', head: true })
      .eq('organization_id', orgId).is('removed_at', null)
      .gte('completed_at', dayStart).lte('completed_at', dayEnd),
    admin.from('work_orders').select('id', { count: 'exact', head: true })
      .eq('organization_id', orgId).is('removed_at', null)
      .in('status', ['open', 'in_progress', 'on_hold']).lt('due_at', nowIso),
    admin.from('daily_logs').select('id', { count: 'exact', head: true })
      .eq('organization_id', orgId).is('removed_at', null).eq('log_date', day),
    admin.from('notifications').select('id', { count: 'exact', head: true })
      .eq('organization_id', orgId).eq('alarm', true)
      .gte('created_at', dayStart).lte('created_at', dayEnd),
    admin.from('attendance').select('id', { count: 'exact', head: true })
      .eq('organization_id', orgId).is('removed_at', null)
      .eq('work_date', day).eq('status', 'present'),
    admin.from('work_orders').select('title, status, due_at')
      .eq('organization_id', orgId).is('removed_at', null)
      .eq('priority', 'critical').in('status', ['open', 'in_progress', 'on_hold'])
      .order('due_at', { ascending: true }).limit(10),
  ]);

  return {
    woOpen: open.count ?? 0,
    woClosed: closed.count ?? 0,
    woOverdue: overdue.count ?? 0,
    logs: logs.count ?? 0,
    alarms: alarms.count ?? 0,
    present: attend.count ?? 0,
    critical: (critical.data ?? []).map((w) => ({
      title: String(w.title), status: String(w.status), due: w.due_at,
    })),
  };
}

function renderEmail(company: string, day: string, s: Summary, footer: string): string {
  const cell = (label: string, value: number, colour: string) => `
    <td style="padding:14px 10px;text-align:center;background:#0f172a;border-radius:8px">
      <div style="font:700 26px/1 -apple-system,Segoe UI,Roboto,sans-serif;color:${colour}">${value}</div>
      <div style="font:400 12px/1.4 -apple-system,Segoe UI,Roboto,sans-serif;color:#94a3b8;padding-top:6px">${label}</div>
    </td>`;

  const criticalRows = s.critical.length
    ? s.critical.map((w) => `
        <tr>
          <td style="padding:8px 10px;border-bottom:1px solid #1e293b;font:400 13px/1.4 -apple-system,Segoe UI,Roboto,sans-serif;color:#e2e8f0">${esc(w.title)}</td>
          <td style="padding:8px 10px;border-bottom:1px solid #1e293b;font:400 13px/1.4 -apple-system,Segoe UI,Roboto,sans-serif;color:#94a3b8">${esc(w.status)}</td>
          <td style="padding:8px 10px;border-bottom:1px solid #1e293b;font:400 13px/1.4 -apple-system,Segoe UI,Roboto,sans-serif;color:#94a3b8">${w.due ? esc(String(w.due).slice(0, 10)) : '—'}</td>
        </tr>`).join('')
    : `<tr><td colspan="3" style="padding:12px 10px;font:400 13px -apple-system,Segoe UI,Roboto,sans-serif;color:#64748b">No critical work orders open.</td></tr>`;

  return `<!doctype html><html><body style="margin:0;padding:24px;background:#020617">
<table role="presentation" width="100%" style="max-width:640px;margin:0 auto;background:#0b1220;border:1px solid #1e293b;border-radius:14px">
  <tr><td style="padding:22px 24px;border-bottom:1px solid #1e293b">
    <div style="font:700 19px -apple-system,Segoe UI,Roboto,sans-serif;color:#f1f5f9">${esc(company)}</div>
    <div style="font:400 13px -apple-system,Segoe UI,Roboto,sans-serif;color:#7aa2f7;padding-top:4px">Daily maintenance summary — ${esc(day)}</div>
  </td></tr>
  <tr><td style="padding:18px 16px">
    <table role="presentation" width="100%" style="border-spacing:8px 0">
      <tr>${cell('Open', s.woOpen, '#7aa2f7')}${cell('Closed today', s.woClosed, '#34d399')}${cell('Overdue', s.woOverdue, s.woOverdue ? '#f87171' : '#94a3b8')}</tr>
    </table>
    <table role="presentation" width="100%" style="border-spacing:8px;margin-top:4px">
      <tr>${cell('Log entries', s.logs, '#cbd5e1')}${cell('Alarms', s.alarms, s.alarms ? '#fbbf24' : '#94a3b8')}${cell('Present', s.present, '#cbd5e1')}</tr>
    </table>
  </td></tr>
  <tr><td style="padding:6px 24px 20px">
    <div style="font:700 14px -apple-system,Segoe UI,Roboto,sans-serif;color:#f1f5f9;padding-bottom:8px">Critical work orders</div>
    <table role="presentation" width="100%" style="border-collapse:collapse">${criticalRows}</table>
  </td></tr>
  <tr><td style="padding:16px 24px;border-top:1px solid #1e293b;font:400 12px/1.6 -apple-system,Segoe UI,Roboto,sans-serif;color:#64748b">
    ${esc(footer)}<br>Sent by PlantMaster Pro · <a href="https://app.hsbfix.org" style="color:#7aa2f7;text-decoration:none">Open the app</a>
  </td></tr>
</table></body></html>`;
}

Deno.serve(async (req) => {
  const json = (d: unknown, status = 200) =>
    new Response(JSON.stringify(d), { status, headers: { 'Content-Type': 'application/json' } });

  if (req.method !== 'POST') return json({ ok: false, error: 'Method not allowed' }, 405);

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { /* ignore */ }

  const expected = env('DAILY_REPORTS_TOKEN');
  const provided = req.headers.get('x-internal-token') || String(body.token || '');
  if (!expected) return json({ ok: false, error: 'Server misconfigured' }, 500);
  if (!safeEqual(expected, provided)) return json({ ok: false, error: 'Forbidden' }, 403);

  const admin = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false },
  });

  const resendKey = env('RESEND_API_KEY');
  const fromAddress = env('REPORT_FROM') || 'PlantMaster Pro <reports@hsbfix.org>';
  const force = body.force === true;
  const windowMinutes = Number(body.window_minutes ?? 90);

  const { data: orgs, error } = await admin
    .from('organizations')
    .select('id, name, timezone, commercial_status, removed_at')
    .is('removed_at', null)
    .in('commercial_status', ['trial', 'active', 'past_due']);

  if (error) return json({ ok: false, error: error.message }, 500);

  const results: Record<string, unknown>[] = [];
  let sent = 0, skipped = 0;

  for (const org of orgs ?? []) {
    const { data: settings } = await admin
      .from('organization_settings')
      .select('report_time, report_recipients, email, footer_text')
      .eq('organization_id', org.id)
      .maybeSingle();

    const recipients = String(settings?.report_recipients || settings?.email || '')
      .split(/[,;\s]+/).map((r) => r.trim())
      .filter((r) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(r));

    if (!recipients.length) { skipped++; continue; }

    const tz = String(org.timezone || 'Asia/Karachi');
    const { date: today, minutes: nowMinutes } = localNow(tz);
    const [h, m] = String(settings?.report_time || '11:00').split(':');
    const target = Number(h) * 60 + Number(m || 0);

    // Due if the scheduled minute has passed today, within the catch-up window.
    const due = force || (nowMinutes >= target && nowMinutes - target <= windowMinutes);
    if (!due) { skipped++; continue; }

    // Idempotency: the unique index rejects a second row for the same day.
    const { error: claimErr } = await admin
      .from('daily_report_runs')
      .insert({ organization_id: org.id, report_date: today, recipients: recipients.length });
    if (claimErr) { skipped++; continue; } // already sent today

    try {
      const summary = await buildSummary(admin, org.id, today);
      const html = renderEmail(
        String(org.name), today, summary,
        String(settings?.footer_text || 'HSB Fix Services, Karachi, Pakistan'),
      );

      if (!resendKey) throw new Error('RESEND_API_KEY is not configured');

      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { Authorization: `Bearer ${resendKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          from: fromAddress,
          to: recipients,
          subject: `${org.name} — daily summary ${today}`,
          html,
        }),
      });

      if (!res.ok) throw new Error(`Resend ${res.status}: ${(await res.text()).slice(0, 200)}`);

      await admin.from('daily_report_runs')
        .update({ status: 'sent', sent_at: new Date().toISOString() })
        .eq('organization_id', org.id).eq('report_date', today);

      sent++;
      results.push({ org: org.name, recipients: recipients.length, status: 'sent' });

    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      // Record the failure but leave the claim row so a retry storm cannot
      // mail the same company repeatedly; status shows it needs attention.
      await admin.from('daily_report_runs')
        .update({ status: 'failed', error: message.slice(0, 500) })
        .eq('organization_id', org.id).eq('report_date', today);
      console.error(`daily-report ${org.id} failed: ${message}`);
      results.push({ org: org.name, status: 'failed', error: message.slice(0, 200) });
    }
  }

  return json({ ok: true, sent, skipped, total: orgs?.length ?? 0, results });
});
