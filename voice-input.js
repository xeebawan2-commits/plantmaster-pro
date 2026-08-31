// PlantMaster Pro v4.13 — Global Voice Typing
// Works in EVERY text field of the app (search, forms, notes, work orders, solver…).
//   Tap the mic      = speak in the current language (default: English)
//   Long-press mic   = switch language (EN <-> اردو)
//   Urdu speech      = automatically converted to English and typed into the field
// Requires: HTTPS + Chrome (SpeechRecognition). The mic hides itself on unsupported browsers.
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js?v=4.3.1';

const Rec = window.SpeechRecognition || window.webkitSpeechRecognition;
if (Rec && isSecureContext) {
  let lang = 'en';            // 'en' | 'ur'
  let recognition = null;
  let listening = false;
  let lastField = null;
  let pressTimer = null;
  let didLongPress = false;

  const isTextField = (t) => !!t && (
    t.tagName === 'TEXTAREA' ||
    (t.tagName === 'INPUT' && !/^(checkbox|radio|button|submit|reset|file|password)$/i.test(t.type || ''))
  );

  // remember the most recently focused text field
  document.addEventListener('focusin', (e) => { if (isTextField(e.target)) lastField = e.target; }, true);

  // ---------- self-injected UI (uses the app's theme variables) ----------
  const style = document.createElement('style');
  style.textContent = `
  #pmVoiceFab{position:fixed;right:16px;bottom:calc(84px + env(safe-area-inset-bottom));z-index:60;width:58px;height:58px;border-radius:50%;
    border:none;cursor:pointer;background:var(--brand,#0b9dd4);color:#fff;font-size:24px;line-height:1;
    box-shadow:0 6px 18px rgba(0,0,0,.45);display:flex;align-items:center;justify-content:center;touch-action:manipulation}
  #pmVoiceFab .pm-voice-badge{position:absolute;top:-4px;left:-2px;background:#fff;color:#0b2440;font-size:9px;font-weight:800;
    padding:2px 5px;border-radius:8px;letter-spacing:.3px}
  #pmVoiceFab.listening{background:#e5484d;animation:pmVoicePulse 1.1s ease-in-out infinite}
  @keyframes pmVoicePulse{0%,100%{transform:scale(1)}50%{transform:scale(1.12)}}
  #pmVoiceBubble{position:fixed;right:16px;bottom:calc(152px + env(safe-area-inset-bottom));z-index:60;max-width:min(320px,80vw);
    background:rgba(10,25,45,.96);color:#eaf3ff;border:1px solid rgba(120,180,255,.35);border-radius:14px;padding:10px 12px;
    font-size:13px;line-height:1.45;box-shadow:0 8px 24px rgba(0,0,0,.5)}
  #pmVoiceBubble small{opacity:.75;display:block;margin-top:3px}`;
  document.head.appendChild(style);

  const fab = document.createElement('button');
  fab.id = 'pmVoiceFab';
  fab.setAttribute('aria-label', 'Voice typing');
  fab.innerHTML = '<span class="pm-voice-badge">EN</span>🎙';
  document.body.appendChild(fab);

  const bubble = document.createElement('div');
  bubble.id = 'pmVoiceBubble';
  bubble.hidden = true;
  document.body.appendChild(bubble);

  let bubbleTimer = null;
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  function say(html, ms) {
    clearTimeout(bubbleTimer);
    bubble.hidden = false;
    bubble.innerHTML = html;
    if (ms) bubbleTimer = setTimeout(() => (bubble.hidden = true), ms);
  }

  // ---------- session token (same pattern as push-client.js) ----------
  const readToken = () => {
    for (const k of Object.keys(localStorage)) {
      if (!/sb-.*-auth-token$/.test(k)) continue;
      try {
        const j = JSON.parse(localStorage.getItem(k));
        const t = j?.currentSession?.access_token || j?.sessionId;
        if (t) return t;
      } catch (_) {}
    }
    return null;
  };

  const targetField = () => {
    const a = document.activeElement;
    if (isTextField(a)) return a;
    if (lastField && document.contains(lastField)) return lastField;
    return null;
  };

  function insertAtCaret(el, text) {
    const s = typeof el.selectionStart === 'number' ? el.selectionStart : el.value.length;
    const e = typeof el.selectionEnd === 'number' ? el.selectionEnd : s;
    el.value = el.value.slice(0, s) + text + el.value.slice(e);
    const pos = s + text.length;
    try { el.setSelectionRange(pos, pos); } catch (_) {}
    if (/[\u0600-\u06ff]/.test(text)) el.dir = 'rtl';
    el.dispatchEvent(new Event('input', { bubbles: true }));
  }

  async function translateToEnglish(text) {
    const tok = readToken();
    if (!tok) throw new Error('no-session');
    const r = await fetch(SUPABASE_URL + '/functions/v1/voice-translate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: SUPABASE_ANON_KEY, Authorization: 'Bearer ' + tok },
      body: JSON.stringify({ text })
    });
    const d = await r.json().catch(() => ({}));
    if (!r.ok || d.error) throw new Error(d.error || 'translation-failed');
    return d;
  }

  function stopRecognition() { try { recognition && recognition.stop(); } catch (_) {} }

  function start() {
    const el = targetField();
    if (!el) { say('⌨️ Tap a text box first, then tap the mic', 2500); return; }
    el.focus();
    stopRecognition();
    recognition = new Rec();
    recognition.lang = lang === 'ur' ? 'ur-PK' : 'en-PK';
    recognition.interimResults = true;
    recognition.continuous = false;
    let heard = '';
    listening = true;
    fab.classList.add('listening');
    if (navigator.vibrate) navigator.vibrate(30);
    say('🎙 ' + (lang === 'ur' ? 'سن رہے ہیں… اردو میں بولیں' : 'Listening… speak now'));
    recognition.onresult = (e) => {
      let t = '';
      for (let i = e.resultIndex; i < e.results.length; i++) t += e.results[i][0].transcript;
      heard = t;
      say('🎙 ' + (esc(t) || '…'));
    };
    recognition.onerror = (e) => {
      if (e.error && e.error !== 'no-speech' && e.error !== 'aborted') say('Microphone: ' + e.error, 2500);
    };
    recognition.onend = async () => {
      listening = false;
      fab.classList.remove('listening');
      if (navigator.vibrate) navigator.vibrate(20);
      const text = heard.trim();
      if (!text) { say('Nothing heard — try again', 2200); return; }
      // English speech (or non-Urdu text) goes in as-is
      if (lang === 'en' || !/[\u0600-\u06ff]/.test(text)) {
        insertAtCaret(el, text);
        say('✓ Added to text box', 1500);
        return;
      }
      // Urdu speech -> convert to English, type that
      say('⏳ Converting Urdu → English…');
      try {
        const d = await translateToEnglish(text);
        const en = String(d.english || d.text || '').trim() || text;
        insertAtCaret(el, en);
        say('✓ Typed in English<small dir="rtl">' + esc(text) + '</small>', 4500);
      } catch (err) {
        // never lose the user's words: fall back to the raw Urdu transcript
        insertAtCaret(el, text);
        say((err && err.message === 'no-session')
          ? 'Sign in first, then use voice'
          : '⚠️ Conversion unavailable — your Urdu words were added as-is', 4000);
      }
    };
    try { recognition.start(); } catch (_) { say('Microphone is busy', 2000); }
  }

  function setLang(l) {
    lang = l;
    fab.querySelector('.pm-voice-badge').textContent = l === 'ur' ? 'اردو' : 'EN';
  }

  // tap = speak · long-press (600ms) = switch language
  fab.addEventListener('pointerdown', () => {
    didLongPress = false;
    pressTimer = setTimeout(() => {
      didLongPress = true;
      if (navigator.vibrate) navigator.vibrate(30);
      setLang(lang === 'en' ? 'ur' : 'en');
      say(lang === 'ur' ? '🎙 اردو میں بولیں — لکھائی انگریزی ہوگی' : '🎙 Speak in English', 2600);
    }, 600);
  });
  fab.addEventListener('pointerup', () => { clearTimeout(pressTimer); if (!didLongPress) start(); });
  fab.addEventListener('pointercancel', () => clearTimeout(pressTimer));
  fab.addEventListener('pointerleave', () => clearTimeout(pressTimer));
  fab.addEventListener('contextmenu', (e) => e.preventDefault());

  setLang('en');
}
