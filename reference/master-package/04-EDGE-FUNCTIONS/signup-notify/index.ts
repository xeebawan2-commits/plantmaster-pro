/* PlantMaster Pro — signup-notify edge function v1.0.0
 *
 * Fires when a prospect submits the form on hsbfix.org.
 *   1. Sends the prospect a "thank you for applying" acknowledgement.
 *   2. Sends YOU an alert so the enquiry is never missed.
 *
 * It creates NO account and grants NO access. The request still has to be
 * approved in the Control Center before anyone can open a workspace.
 *
 * POST /  { "request_id": "<uuid of the signup_requests row>" }
 *
 * Called by a database trigger (see 02-SIGNUP-EMAIL.sql) or directly.
 *
 * Secrets required:
 *   RESEND_API_KEY        re_xxx                (already set for daily-reports)
 *   SIGNUP_FROM           'HSB Fix Services <support@hsbfix.org>'
 *   SIGNUP_ALERT_TO       where YOUR alert goes, e.g. support@hsbfix.org
 *   SUPABASE_URL          (provided automatically)
 *   SUPABASE_SERVICE_ROLE_KEY / SUPABASE_SECRET_KEY
 *
 * IMPORTANT: set Verify JWT = OFF for this function, and re-check it after
 * every redeploy — Supabase silently turns it back on.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } });

const esc = (v: unknown) =>
  String(v ?? '').replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c] as string));

function applicantHtml(name: string, company: string) {
  return `<!doctype html><html><body style="margin:0;padding:0;background:#f4f5f7">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f5f7;padding:24px 12px">
<tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border:1px solid #e2e5ea;border-radius:14px;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif">
  <tr><td style="background:#0f9b8e;padding:22px 26px">
    <div style="color:#ffffff;font-size:19px;font-weight:700;line-height:1.3">HSB Fix Services</div>
    <div style="color:#d6f3ef;font-size:12px;letter-spacing:.10em;text-transform:uppercase;margin-top:3px">PlantMaster&nbsp;Pro</div>
  </td></tr>
  <tr><td style="padding:28px 26px;color:#0d1117;font-size:15px;line-height:1.62">
    <p style="margin:0 0 16px">Dear ${esc(name)},</p>
    <p style="margin:0 0 16px">Thank you for applying for a PlantMaster&nbsp;Pro trial for <b>${esc(company)}</b>. We have received your request.</p>
    <p style="margin:0 0 10px"><b>What happens next</b></p>
    <ol style="margin:0 0 18px;padding-left:20px;color:#3a4149">
      <li style="margin-bottom:7px">We review your request, usually within one working day.</li>
      <li style="margin-bottom:7px">We contact you on WhatsApp to understand your plant and answer questions.</li>
      <li style="margin-bottom:7px">Once approved, we create your company workspace and send your sign-in details.</li>
    </ol>
    <p style="margin:0 0 16px;padding:13px 15px;background:#f0faf8;border-left:3px solid #0f9b8e;border-radius:0 8px 8px 0;color:#124f49;font-size:14px">
      Accounts are opened by us, not self-service. This keeps every plant's data separate and properly set up before your team starts.
    </p>
    <p style="margin:0 0 18px">Your 7-day trial runs on full Professional features and starts when we activate your workspace, so none of it is wasted while you wait.</p>
    <p style="margin:0 0 6px">If anything is urgent, reply to this email or message us:</p>
    <p style="margin:0 0 22px"><a href="https://wa.me/923162364074" style="color:#0f9b8e;font-weight:600;text-decoration:none">WhatsApp +92&nbsp;316&nbsp;2364074</a></p>
    <p style="margin:0;color:#5b636d">Thank you,<br><b style="color:#0d1117">HSB Fix Services</b></p>
  </td></tr>
  <tr><td style="padding:15px 26px;background:#fafbfc;border-top:1px solid #eceff2;color:#7b838d;font-size:12px;line-height:1.55">
    support@hsbfix.org &nbsp;•&nbsp; <a href="https://hsbfix.org" style="color:#7b838d">hsbfix.org</a><br>
    You are receiving this because you requested a trial at hsbfix.org.
  </td></tr>
</table></td></tr></table></body></html>`;
}

function alertHtml(r: Record<string, unknown>) {
  const row = (k: string, v: unknown) =>
    v ? `<tr><td style="padding:5px 12px 5px 0;color:#6b7280;font-size:13px;white-space:nowrap">${esc(k)}</td><td style="padding:5px 0;color:#0d1117;font-size:14px"><b>${esc(v)}</b></td></tr>` : '';
  const phone = String(r.phone ?? '').replace(/\D/g, '').replace(/^0/, '92');
  return `<!doctype html><html><body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif;background:#f4f5f7;padding:20px">
<div style="max-width:540px;margin:auto;background:#fff;border:1px solid #e2e5ea;border-radius:12px;padding:22px">
  <h2 style="margin:0 0 4px;font-size:17px;color:#0d1117">New trial request</h2>
  <p style="margin:0 0 16px;color:#6b7280;font-size:13px">Approve or reject in the Control Center.</p>
  <table cellpadding="0" cellspacing="0">
    ${row('Company', r.company_name)}${row('Contact', r.contact_name)}${row('Email', r.email)}
    ${row('Phone', r.phone)}${row('City', r.city)}${row('Industry', r.plant_type)}
    ${row('Team size', r.team_size)}${row('Interested in', r.plan_interest)}
  </table>
  ${r.message ? `<p style="margin:14px 0 0;padding:11px 13px;background:#f7f8fa;border-radius:8px;color:#3a4149;font-size:13.5px;line-height:1.55">${esc(r.message)}</p>` : ''}
  <div style="margin-top:20px">
    <a href="https://admin.hsbfix.org" style="display:inline-block;background:#0f9b8e;color:#fff;padding:10px 17px;border-radius:8px;text-decoration:none;font-weight:600;font-size:14px">Open Control Center</a>
    ${phone ? `<a href="https://wa.me/${phone}" style="display:inline-block;margin-left:8px;background:#25d366;color:#fff;padding:10px 17px;border-radius:8px;text-decoration:none;font-weight:600;font-size:14px">WhatsApp</a>` : ''}
  </div>
</div></body></html>`;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const resendKey = Deno.env.get('RESEND_API_KEY');
    if (!resendKey) return json({ error: 'RESEND_API_KEY not configured' }, 500);

    const from = Deno.env.get('SIGNUP_FROM') || 'HSB Fix Services <support@hsbfix.org>';
    const alertTo = Deno.env.get('SIGNUP_ALERT_TO') || 'support@hsbfix.org';
    const url = Deno.env.get('SUPABASE_URL')!;
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SECRET_KEY')!;

    const body = await req.json().catch(() => ({}));
    const id = String(body.request_id || body.record?.id || '');
    const byEmail = String(body.email || '').trim().toLowerCase();
    if (!id && !byEmail) return json({ error: 'request_id or email is required' }, 400);

    const admin = createClient(url, key, { auth: { persistSession: false } });

    // Look up by id when a trigger calls us, or by the newest matching email
    // when the website calls us straight after inserting the row.
    // Only ever reads a row the caller just created; nothing is exposed in the
    // response, so this cannot be used to enumerate other people's enquiries.
    const q = admin.from('signup_requests').select('*');
    const { data: r, error } = id
      ? await q.eq('id', id).maybeSingle()
      : await q.eq('email', byEmail).order('created_at', { ascending: false }).limit(1).maybeSingle();
    if (error) return json({ error: error.message }, 500);
    if (!r) return json({ error: 'Request not found' }, 404);

    // Idempotency guard. Both the website and (optionally) a database trigger
    // can call this. Whichever arrives second must not email the applicant twice.
    if (r.ack_sent_at && !body.force) {
      return json({ ok: true, skipped: 'already acknowledged', ack_sent_at: r.ack_sent_at });
    }

    const send = (to: string, subject: string, html: string) =>
      fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { Authorization: 'Bearer ' + resendKey, 'Content-Type': 'application/json' },
        body: JSON.stringify({ from, to, subject, html }),
      });

    // 1. acknowledge the applicant
    const a = await send(
      r.email,
      'Thank you for applying — PlantMaster Pro',
      applicantHtml(r.contact_name || 'there', r.company_name || 'your plant'),
    );
    const aj = await a.json().catch(() => ({}));

    // 2. alert the operator (never blocks the acknowledgement)
    let bj: Record<string, unknown> = {};
    try {
      const b = await send(alertTo, `New trial request — ${r.company_name}`, alertHtml(r));
      bj = await b.json().catch(() => ({}));
    } catch (_) { /* ignore */ }

    // record that we acknowledged, so the Control Center can show it
    await admin.from('signup_requests')
      .update({ ack_sent_at: new Date().toISOString() }).eq('id', r.id);

    return json({ ok: a.ok, applicant: aj, alert: bj });
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
