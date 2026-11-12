// The tally-app.dev contact form: validates a submission and e-mails it to the owner through
// Cloudflare Email Routing (`send_email` binding). Pure apart from the injected `deps`, so it
// runs under `node --test` without the Workers runtime.
//
// Nothing is stored. The recipient comes from the CONTACT_TO secret (set in the Cloudflare
// dashboard, never committed), and it must be a verified Email Routing destination address.

export const FROM_ADDRESS = "website@tally-app.dev";
export const FROM_NAME = "Tally website";

export const TOPICS = Object.freeze({
  question: "A question about Tally",
  help: "Help with the app",
  school: "My school or Canvas setup",
  press: "Press",
  other: "Something else",
});

export const LIMITS = Object.freeze({
  name: 100,
  email: 254,
  messageMin: 5,
  messageMax: 5000,
  bodyBytes: 20000,
  // A human takes longer than this to fill the form; bots usually don't.
  minFillMs: 3000,
});

const EMAIL_PATTERN = /^[^\s@<>"(),;:\\]+@[^\s@<>"(),;:\\]+\.[^\s@<>"(),;:\\]+$/;

/** Collapses every control character, CR and LF included, so no value can add a header line. */
export function singleLine(value) {
  return String(value ?? "").replace(/[\u0000-\u001f\u007f]+/g, " ").trim();
}

/** Normalizes line endings and drops control characters other than tab and newline. */
export function multiLine(value) {
  return String(value ?? "")
    .replace(/\r\n?/g, "\n")
    .replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, "")
    .trim();
}

/**
 * Validates raw form fields.
 * @returns {{status: "ok", value: object} | {status: "spam"} | {status: "invalid", fields: string[]}}
 */
export function parseSubmission(fields, nowMs) {
  const honeypot = singleLine(fields.website);
  const startedMs = Number(fields.started);
  if (honeypot) return { status: "spam" };
  if (Number.isFinite(startedMs) && startedMs > 0 && nowMs - startedMs < LIMITS.minFillMs) return { status: "spam" };

  const name = singleLine(fields.name).slice(0, LIMITS.name);
  const email = singleLine(fields.email);
  const topicKey = Object.hasOwn(TOPICS, fields.topic) ? fields.topic : "other";
  const message = multiLine(fields.message);

  const invalid = [];
  if (email.length > LIMITS.email || !EMAIL_PATTERN.test(email)) invalid.push("email");
  if (message.length < LIMITS.messageMin || message.length > LIMITS.messageMax) invalid.push("message");
  if (invalid.length) return { status: "invalid", fields: invalid };

  return { status: "ok", value: { name, email, topicKey, topic: TOPICS[topicKey], message } };
}

function utf8Base64(text) {
  const bytes = new TextEncoder().encode(text);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

/** RFC 2047 encoded-word for a header value that isn't plain ASCII. */
export function encodeHeader(value) {
  return /^[\x20-\x7e]*$/.test(value) ? value : `=?UTF-8?B?${utf8Base64(value)}?=`;
}

/** A plain-text RFC 5322 message, base64 body, CRLF line endings. */
export function buildRawEmail({ to, replyTo, subject, text, date, messageId }) {
  // Header values are flattened again here, whatever the caller passed, so no value can add a header.
  [to, replyTo, subject, messageId] = [to, replyTo, subject, messageId].map(singleLine);
  const body = utf8Base64(text).replace(/.{1,76}/g, "$&\r\n");
  return [
    `From: ${encodeHeader(FROM_NAME)} <${FROM_ADDRESS}>`,
    `To: <${to}>`,
    `Reply-To: <${replyTo}>`,
    `Subject: ${encodeHeader(subject)}`,
    `Date: ${date.toUTCString()}`,
    `Message-ID: <${messageId}@tally-app.dev>`,
    "MIME-Version: 1.0",
    "Content-Type: text/plain; charset=utf-8",
    "Content-Transfer-Encoding: base64",
    "",
    body,
  ].join("\r\n");
}

export function composeEmail(value, to, date, messageId) {
  const text = [
    `Topic: ${value.topic}`,
    `Name: ${value.name || "(not given)"}`,
    `E-mail: ${value.email}`,
    `Sent: ${date.toISOString()}`,
    "",
    value.message,
    "",
    "Reply to this e-mail to answer the sender.",
  ].join("\n");
  return buildRawEmail({ to, replyTo: value.email, subject: `Tally contact form: ${value.topic}`, text, date, messageId });
}

function respond(wantsJson, status, payload, redirectTo) {
  const headers = { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" };
  if (wantsJson) {
    return new Response(JSON.stringify(payload), { status, headers: { ...headers, "Content-Type": "application/json" } });
  }
  return new Response(null, { status: 303, headers: { ...headers, Location: redirectTo } });
}

async function readFields(request) {
  const type = request.headers.get("Content-Type") || "";
  if (type.includes("application/json")) {
    const parsed = await request.json();
    return parsed && typeof parsed === "object" ? parsed : {};
  }
  const form = await request.formData();
  return Object.fromEntries([...form.entries()].map(([key, value]) => [key, typeof value === "string" ? value : ""]));
}

/**
 * Handles POST /api/contact.
 * @param deps {{ makeMessage(from: string, to: string, raw: string): unknown, now(): number, randomId(): string }}
 */
export async function handleContact(request, env, deps) {
  const wantsJson = (request.headers.get("Accept") || "").includes("application/json");
  if (request.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405, headers: { Allow: "POST" } });
  }
  const origin = request.headers.get("Origin");
  if (origin && origin !== new URL(request.url).origin) {
    return respond(wantsJson, 403, { ok: false, error: "forbidden" }, "/contact/?error=forbidden");
  }
  const declaredLength = Number(request.headers.get("Content-Length") || 0);
  if (declaredLength > LIMITS.bodyBytes) {
    return respond(wantsJson, 413, { ok: false, error: "invalid" }, "/contact/?error=invalid");
  }

  let fields;
  try {
    fields = await readFields(request);
  } catch {
    return respond(wantsJson, 400, { ok: false, error: "invalid" }, "/contact/?error=invalid");
  }

  const nowMs = deps.now();
  const result = parseSubmission(fields, nowMs);
  // Spam gets the same answer as a real message, so bots learn nothing.
  if (result.status === "spam") return respond(wantsJson, 200, { ok: true }, "/contact/sent/");
  if (result.status === "invalid") {
    return respond(wantsJson, 400, { ok: false, error: "invalid", fields: result.fields }, "/contact/?error=invalid");
  }
  if (!env.CONTACT_TO || !env.CONTACT_EMAIL) {
    return respond(wantsJson, 503, { ok: false, error: "unavailable" }, "/contact/?error=unavailable");
  }

  const raw = composeEmail(result.value, env.CONTACT_TO, new Date(nowMs), deps.randomId());
  try {
    await env.CONTACT_EMAIL.send(deps.makeMessage(FROM_ADDRESS, env.CONTACT_TO, raw));
  } catch (error) {
    console.error("contact form: send failed", error && error.message);
    return respond(wantsJson, 502, { ok: false, error: "unavailable" }, "/contact/?error=unavailable");
  }
  return respond(wantsJson, 200, { ok: true }, "/contact/sent/");
}
