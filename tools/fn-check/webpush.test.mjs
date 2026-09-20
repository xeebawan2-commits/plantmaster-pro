/**
 * Web Push correctness test.
 *
 * supabase/functions/_shared/webpush.ts implements RFC 8291 (aes128gcm
 * payload encryption) and RFC 8292 (VAPID) by hand. A bug there is invisible
 * until a real phone silently fails to receive an alarm, so this test plays
 * both sides: it generates a browser keypair, has the function encrypt a
 * notification to it, then decrypts it back and verifies the VAPID JWT
 * against the advertised public key.
 *
 * The .ts source is transpiled on the fly so the test always runs against
 * what actually ships, never a copy that can drift.
 */
import { webcrypto } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, cpSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

if (!globalThis.crypto) globalThis.crypto = webcrypto;

const here = dirname(fileURLToPath(import.meta.url));
const work = mkdtempSync(join(tmpdir(), 'pm-webpush-'));
let mod;
try {
  cpSync(join(here, '..', '..', 'supabase', 'functions', '_shared', 'webpush.ts'),
         join(work, 'webpush.ts'));
  execFileSync('npx', ['tsc', join(work, 'webpush.ts'),
    '--target', 'ES2022', '--module', 'ESNext', '--moduleResolution', 'Bundler',
    '--skipLibCheck', '--outDir', work], { cwd: join(here, '..', '..'), stdio: 'pipe' });
  cpSync(join(work, 'webpush.js'), join(work, 'webpush.mjs'));
  mod = await import(pathToFileURL(join(work, 'webpush.mjs')).href);
} finally {
  process.on('exit', () => { try { rmSync(work, { recursive: true, force: true }); } catch {} });
}
const { b64urlToBytes, bytesToB64url, sendPush } = mod;

console.log('\n\x1b[2m── web push (RFC 8291 / 8292) ──\x1b[0m');

let pass = 0, fail = 0;
const ok = (n, c) => { if (c) { pass++; console.log('  \x1b[32m\u2713\x1b[0m ' + n); } else { fail++; console.log('  \x1b[31mFAIL\x1b[0m ' + n); } };

// 1. base64url round-trip on a real p256dh key
const k = 'BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8';
const kb = b64urlToBytes(k);
ok('p256dh decodes to 65 uncompressed bytes', kb.length === 65 && kb[0] === 0x04);
ok('base64url round-trips', bytesToB64url(kb) === k);
ok('padding-free decode matches Buffer', Buffer.from(k, 'base64url').equals(Buffer.from(kb)));

// 2. Intercept the push POST so we can inspect the real encrypted request.
let captured = null;
globalThis.fetch = async (url, init) => {
  captured = { url, init };
  return new Response('', { status: 201 });
};

// Generate a realistic subscription keypair (the "browser" side).
const uaPair = await webcrypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
const uaPub = new Uint8Array(await webcrypto.subtle.exportKey('raw', uaPair.publicKey));
const authSecret = webcrypto.getRandomValues(new Uint8Array(16));

// VAPID keypair (the "server" side).
const vapidPair = await webcrypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
const vapidPubRaw = new Uint8Array(await webcrypto.subtle.exportKey('raw', vapidPair.publicKey));
const vapidJwk = await webcrypto.subtle.exportKey('jwk', vapidPair.privateKey);

const res = await sendPush(
  { endpoint: 'https://fcm.googleapis.com/fcm/send/abc123', keys: { p256dh: bytesToB64url(uaPub), auth: bytesToB64url(authSecret) } },
  { title: 'Pump 3 tripped', body: 'Overload relay', url: '/work-orders' },
  { publicKey: bytesToB64url(vapidPubRaw), privateKey: vapidJwk.d, subject: 'mailto:support@hsbfix.org' },
);

ok('sendPush reports success on 201', res.ok === true && res.status === 201);
ok('Content-Encoding is aes128gcm', captured.init.headers['Content-Encoding'] === 'aes128gcm');
ok('TTL header sent', captured.init.headers.TTL === '86400');

const body = new Uint8Array(captured.init.body);
// RFC 8188 header: 16B salt | 4B rs | 1B idlen | keyid | ciphertext
const rs = new DataView(body.buffer, body.byteOffset).getUint32(16);
const idlen = body[20];
ok('record size field is 4096', rs === 4096);
ok('key id length is 65 (uncompressed P-256 point)', idlen === 65);
ok('ephemeral key is a valid uncompressed point', body[21] === 0x04);
const plaintextLen = JSON.stringify({ title: 'Pump 3 tripped', body: 'Overload relay', url: '/work-orders' }).length;
ok('ciphertext = plaintext + delimiter + GCM tag', body.length - (21 + 65) === plaintextLen + 1 + 16);

// 3. Verify the VAPID JWT actually validates against the advertised key.
const auth = captured.init.headers.Authorization;
ok('Authorization uses the vapid scheme', auth.startsWith('vapid t=') && auth.includes(', k='));
const t = auth.slice(8).split(', k=')[0];
const kParam = auth.split(', k=')[1];
ok('advertised k matches the signing key', kParam === bytesToB64url(vapidPubRaw));
const [h, c, sig] = t.split('.');
const verified = await webcrypto.subtle.verify(
  { name: 'ECDSA', hash: 'SHA-256' }, vapidPair.publicKey,
  Buffer.from(sig, 'base64url'), Buffer.from(`${h}.${c}`),
);
ok('VAPID JWT signature verifies', verified);
const claims = JSON.parse(Buffer.from(c, 'base64url'));
ok('aud is the push origin, not the full endpoint', claims.aud === 'https://fcm.googleapis.com');
ok('exp is within the 24h maximum', claims.exp - Math.floor(Date.now() / 1000) <= 86400);
ok('sub is a contact URI', claims.sub === 'mailto:support@hsbfix.org');

// 4. The receiving browser must be able to decrypt it (full RFC 8291 loop).
const salt = body.slice(0, 16);
const asPub = body.slice(21, 21 + 65);
const ciphertext = body.slice(21 + 65);
const asKey = await webcrypto.subtle.importKey('raw', asPub, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
const shared = new Uint8Array(await webcrypto.subtle.deriveBits({ name: 'ECDH', public: asKey }, uaPair.privateKey, 256));
const hmac = async (key, data) => new Uint8Array(await webcrypto.subtle.sign('HMAC',
  await webcrypto.subtle.importKey('raw', key, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']), data));
const cat = (...a) => { const o = new Uint8Array(a.reduce((n, x) => n + x.length, 0)); let i = 0; for (const x of a) { o.set(x, i); i += x.length; } return o; };
const te = new TextEncoder();
const prk = await hmac(authSecret, shared);
const ikm = (await hmac(prk, cat(te.encode('WebPush: info'), new Uint8Array([0]), uaPub, asPub, new Uint8Array([1])))).slice(0, 32);
const prk2 = await hmac(salt, ikm);
const cek = (await hmac(prk2, cat(te.encode('Content-Encoding: aes128gcm'), new Uint8Array([0]), new Uint8Array([1])))).slice(0, 16);
const nonce = (await hmac(prk2, cat(te.encode('Content-Encoding: nonce'), new Uint8Array([0]), new Uint8Array([1])))).slice(0, 12);
const dec = new Uint8Array(await webcrypto.subtle.decrypt({ name: 'AES-GCM', iv: nonce },
  await webcrypto.subtle.importKey('raw', cek, { name: 'AES-GCM' }, false, ['decrypt']), ciphertext));
ok('final-record delimiter 0x02 present', dec[dec.length - 1] === 2);
const payload = JSON.parse(Buffer.from(dec.slice(0, -1)).toString());
ok('browser decrypts the exact notification', payload.title === 'Pump 3 tripped' && payload.url === '/work-orders');

// 5. Expiry handling
globalThis.fetch = async () => new Response('gone', { status: 410 });
const goneRes = await sendPush(
  { endpoint: 'https://fcm.googleapis.com/fcm/send/x', keys: { p256dh: bytesToB64url(uaPub), auth: bytesToB64url(authSecret) } },
  { title: 'x' }, { publicKey: bytesToB64url(vapidPubRaw), privateKey: vapidJwk.d, subject: 'mailto:s@h.org' });
ok('410 is reported as expired', goneRes.ok === false && goneRes.expired === true);
globalThis.fetch = async () => new Response('boom', { status: 500 });
const errRes = await sendPush(
  { endpoint: 'https://fcm.googleapis.com/fcm/send/x', keys: { p256dh: bytesToB64url(uaPub), auth: bytesToB64url(authSecret) } },
  { title: 'x' }, { publicKey: bytesToB64url(vapidPubRaw), privateKey: vapidJwk.d, subject: 'mailto:s@h.org' });
ok('500 is a failure but not expired', errRes.ok === false && errRes.expired === false);

console.log(`\n\x1b[2m── ${pass} passed, ${fail} failed ──\x1b[0m`);
if (fail) { console.log('\x1b[31mWEB PUSH CHECKS FAILED\x1b[0m'); process.exit(1); }
console.log('\x1b[32mWEB PUSH OK\x1b[0m');
