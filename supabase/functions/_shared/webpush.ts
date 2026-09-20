/**
 * Dependency-free Web Push (RFC 8291 aes128gcm + RFC 8292 VAPID) on Web Crypto.
 *
 * Written by hand rather than pulling a library so the edge function has no
 * third-party supply chain and no CDN dependency at cold start.
 */

const enc = new TextEncoder();

/**
 * Explicitly ArrayBuffer-backed bytes. Web Crypto and fetch both reject
 * SharedArrayBuffer-backed views, and the plain `Uint8Array` alias does not
 * express that, so every helper below is pinned to this type.
 */
type Bytes = Uint8Array<ArrayBuffer>;

function bytes(n: number): Bytes {
  return new Uint8Array(new ArrayBuffer(n)) as Bytes;
}

function utf8(s: string): Bytes {
  const src = enc.encode(s);
  const out = bytes(src.length);
  out.set(src);
  return out;
}

export function b64urlToBytes(s: string): Bytes {
  const pad = '='.repeat((4 - (s.length % 4)) % 4);
  const raw = atob((s + pad).replace(/-/g, '+').replace(/_/g, '/'));
  const out = bytes(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

export function bytesToB64url(b: Uint8Array): string {
  let s = '';
  for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode(...b.subarray(i, i + 0x8000));
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function concat(...parts: Uint8Array[]): Bytes {
  const total = parts.reduce((n, p) => n + p.length, 0);
  const out = bytes(total);
  let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
}

function byte(...values: number[]): Bytes {
  const out = bytes(values.length);
  out.set(values);
  return out;
}

async function hmac(key: Bytes, data: Bytes): Promise<Bytes> {
  const k = await crypto.subtle.importKey('raw', key, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', k, data);
  return new Uint8Array(sig) as Bytes;
}

/** HKDF with a single-block expand, which is all RFC 8291 needs. */
async function hkdf(salt: Bytes, ikm: Bytes, info: Bytes, length: number): Promise<Bytes> {
  const prk = await hmac(salt, ikm);
  const okm = await hmac(prk, concat(info, byte(1)));
  return okm.slice(0, length) as Bytes;
}

export interface PushSubscription {
  endpoint: string;
  keys: { p256dh: string; auth: string };
}

/** Builds the aes128gcm body described by RFC 8291 section 3. */
async function encryptPayload(sub: PushSubscription, payload: string): Promise<Bytes> {
  const uaPublic = b64urlToBytes(sub.keys.p256dh);
  const authSecret = b64urlToBytes(sub.keys.auth);

  const eph = await crypto.subtle.generateKey(
    { name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits'],
  ) as CryptoKeyPair;
  const asPublic = new Uint8Array(await crypto.subtle.exportKey('raw', eph.publicKey)) as Bytes;

  const uaKey = await crypto.subtle.importKey('raw', uaPublic, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const shared = new Uint8Array(
    await crypto.subtle.deriveBits({ name: 'ECDH', public: uaKey }, eph.privateKey, 256),
  ) as Bytes;

  // IKM is derived from the ECDH secret keyed by the subscription auth secret.
  const keyInfo = concat(utf8('WebPush: info'), byte(0), uaPublic, asPublic);
  const ikm = await hkdf(authSecret, shared, keyInfo, 32);

  const salt = crypto.getRandomValues(bytes(16));
  const cek = await hkdf(salt, ikm, concat(utf8('Content-Encoding: aes128gcm'), byte(0)), 16);
  const nonce = await hkdf(salt, ikm, concat(utf8('Content-Encoding: nonce'), byte(0)), 12);

  const aesKey = await crypto.subtle.importKey('raw', cek, { name: 'AES-GCM' }, false, ['encrypt']);
  // 0x02 is the final-record delimiter.
  const plaintext = concat(utf8(payload), byte(2));
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, aesKey, plaintext),
  ) as Bytes;

  const rs = bytes(4);
  new DataView(rs.buffer).setUint32(0, 4096);
  return concat(salt, rs, byte(asPublic.length), asPublic, ciphertext);
}

/** Signs the VAPID ES256 JWT for one push origin. */
async function vapidHeader(audience: string, publicKey: string, privateKey: string, subject: string) {
  const pub = b64urlToBytes(publicKey);
  if (pub.length !== 65 || pub[0] !== 4) throw new Error('VAPID_PUBLIC_KEY must be a 65-byte uncompressed P-256 point');

  const jwk: JsonWebKey = {
    kty: 'EC',
    crv: 'P-256',
    x: bytesToB64url(pub.slice(1, 33)),
    y: bytesToB64url(pub.slice(33, 65)),
    d: bytesToB64url(b64urlToBytes(privateKey)),
    ext: true,
  };
  const key = await crypto.subtle.importKey('jwk', jwk, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);

  const header = bytesToB64url(enc.encode(JSON.stringify({ typ: 'JWT', alg: 'ES256' })));
  const claims = bytesToB64url(enc.encode(JSON.stringify({
    aud: audience,
    exp: Math.floor(Date.now() / 1000) + 12 * 3600,
    sub: subject,
  })));
  const signingInput = `${header}.${claims}`;
  const sig = new Uint8Array(
    await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, utf8(signingInput)),
  ) as Bytes;
  return `vapid t=${signingInput}.${bytesToB64url(sig)}, k=${publicKey}`;
}

export interface SendResult {
  ok: boolean;
  status: number;
  /** True when the endpoint is permanently gone and the row should be deleted. */
  expired: boolean;
  error?: string;
}

export async function sendPush(
  sub: PushSubscription,
  payload: Record<string, unknown>,
  vapid: { publicKey: string; privateKey: string; subject: string },
  ttlSeconds = 86400,
): Promise<SendResult> {
  try {
    const audience = new URL(sub.endpoint).origin;
    const [body, authorization] = await Promise.all([
      encryptPayload(sub, JSON.stringify(payload)),
      vapidHeader(audience, vapid.publicKey, vapid.privateKey, vapid.subject),
    ]);

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15_000);
    try {
      const res = await fetch(sub.endpoint, {
        method: 'POST',
        headers: {
          Authorization: authorization,
          'Content-Encoding': 'aes128gcm',
          'Content-Type': 'application/octet-stream',
          TTL: String(ttlSeconds),
          Urgency: 'normal',
        },
        body,
        signal: controller.signal,
      });
      // 404/410 mean the browser dropped the subscription for good.
      const expired = res.status === 404 || res.status === 410;
      if (!res.ok) {
        const text = await res.text().catch(() => '');
        return { ok: false, status: res.status, expired, error: text.slice(0, 200) };
      }
      return { ok: true, status: res.status, expired: false };
    } finally {
      clearTimeout(timer);
    }
  } catch (e) {
    return { ok: false, status: 0, expired: false, error: e instanceof Error ? e.message : String(e) };
  }
}
