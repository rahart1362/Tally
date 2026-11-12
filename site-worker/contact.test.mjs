// node --test site-worker/contact.test.mjs  (Node 20+; no dependencies)
import { test } from "node:test";
import assert from "node:assert/strict";
import { parseSubmission, singleLine, buildRawEmail, composeEmail, handleContact, FROM_ADDRESS, LIMITS } from "./contact.js";

const NOW = Date.UTC(2026, 10, 12, 18, 0, 0);
const good = { name: "Alex Sample", email: "alex@example.test", topic: "help", message: "How do I refresh?", started: String(NOW - 10_000), website: "" };

test("a normal submission is accepted", () => {
  const r = parseSubmission(good, NOW);
  assert.equal(r.status, "ok");
  assert.equal(r.value.topic, "Help with the app");
});

test("the honeypot and a too-fast fill are treated as spam", () => {
  assert.equal(parseSubmission({ ...good, website: "http://spam" }, NOW).status, "spam");
  assert.equal(parseSubmission({ ...good, started: String(NOW - 500) }, NOW).status, "spam");
});

test("a bad e-mail or a too-short or too-long message is invalid", () => {
  assert.deepEqual(parseSubmission({ ...good, email: "nope" }, NOW), { status: "invalid", fields: ["email"] });
  assert.deepEqual(parseSubmission({ ...good, message: "hi" }, NOW), { status: "invalid", fields: ["message"] });
  assert.deepEqual(parseSubmission({ ...good, message: "x".repeat(LIMITS.messageMax + 1) }, NOW), { status: "invalid", fields: ["message"] });
});

test("an unknown topic falls back to 'Something else'", () => {
  assert.equal(parseSubmission({ ...good, topic: "__proto__" }, NOW).value.topic, "Something else");
});

test("header values can't carry a line break", () => {
  assert.equal(singleLine("a\r\nBcc: victim@example.test"), "a Bcc: victim@example.test");
  const r = parseSubmission({ ...good, email: "alex@example.test\r\nBcc: x@example.test" }, NOW);
  assert.equal(r.status, "invalid");
  const raw = composeEmail({ ...r, name: "A\r\nB", email: "alex@example.test", topic: "Help\r\nX: y", message: "m" }, "owner@example.test", new Date(NOW), "id");
  const names = raw.split("\r\n\r\n")[0].split("\r\n").map((line) => line.split(":")[0]);
  assert.deepEqual(names, ["From", "To", "Reply-To", "Subject", "Date", "Message-ID", "MIME-Version", "Content-Type", "Content-Transfer-Encoding"]);
});

test("buildRawEmail flattens line breaks in To, Reply-To and Message-ID", () => {
  const raw = buildRawEmail({ to: "owner@example.test\r\nBcc: a@example.test", replyTo: "x@example.test\nBcc: b@example.test",
    subject: "s", text: "t", date: new Date(NOW), messageId: "id\r\nX-Evil: 1" });
  const names = raw.split("\r\n\r\n")[0].split("\r\n").map((line) => line.split(":")[0]);
  assert.deepEqual(names, ["From", "To", "Reply-To", "Subject", "Date", "Message-ID", "MIME-Version", "Content-Type", "Content-Transfer-Encoding"]);
});

test("the raw message has the required headers and a base64 UTF-8 body", () => {
  const raw = buildRawEmail({ to: "owner@example.test", replyTo: "alex@example.test", subject: "Tally contact form: Press",
    text: "Olá — ünïcödé", date: new Date(NOW), messageId: "abc" });
  const [head, body] = raw.split("\r\n\r\n");
  assert.match(head, new RegExp(`^From: Tally website <${FROM_ADDRESS}>`));
  assert.match(head, /\r\nReply-To: <alex@example\.test>/);
  assert.match(head, /\r\nMessage-ID: <abc@tally-app\.dev>/);
  assert.equal(Buffer.from(body.replace(/\r\n/g, ""), "base64").toString("utf8"), "Olá — ünïcödé");
});

function deps(sent) {
  return { makeMessage: (from, to, raw) => ({ from, to, raw }), now: () => NOW, randomId: () => "rid" };
}
function post(body, headers = {}) {
  return new Request("https://tally-app.dev/api/contact", { method: "POST", body, headers: { Origin: "https://tally-app.dev", ...headers } });
}

test("a JSON post sends one e-mail to CONTACT_TO and returns ok", async () => {
  const sent = [];
  const env = { CONTACT_TO: "owner@example.test", CONTACT_EMAIL: { send: async (m) => sent.push(m) } };
  const res = await handleContact(post(JSON.stringify(good), { "Content-Type": "application/json", Accept: "application/json" }), env, deps());
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true });
  assert.equal(sent.length, 1);
  assert.equal(sent[0].from, FROM_ADDRESS);
  assert.equal(sent[0].to, "owner@example.test");
});

test("a plain form post redirects to the sent page", async () => {
  const env = { CONTACT_TO: "owner@example.test", CONTACT_EMAIL: { send: async () => {} } };
  const res = await handleContact(post(new URLSearchParams(good)), env, deps());
  assert.equal(res.status, 303);
  assert.equal(res.headers.get("Location"), "/contact/sent/");
});

test("spam is answered like success but nothing is sent", async () => {
  const sent = [];
  const env = { CONTACT_TO: "owner@example.test", CONTACT_EMAIL: { send: async (m) => sent.push(m) } };
  const res = await handleContact(post(JSON.stringify({ ...good, website: "x" }), { "Content-Type": "application/json", Accept: "application/json" }), env, deps());
  assert.equal(res.status, 200);
  assert.equal(sent.length, 0);
});

test("another site's form, GET, a missing secret and a send failure are refused", async () => {
  const ok = { CONTACT_TO: "owner@example.test", CONTACT_EMAIL: { send: async () => {} } };
  const json = { "Content-Type": "application/json", Accept: "application/json" };
  assert.equal((await handleContact(post(JSON.stringify(good), { ...json, Origin: "https://evil.example" }), ok, deps())).status, 403);
  assert.equal((await handleContact(new Request("https://tally-app.dev/api/contact"), ok, deps())).status, 405);
  assert.equal((await handleContact(post(JSON.stringify(good), json), {}, deps())).status, 503);
  const failing = { CONTACT_TO: "owner@example.test", CONTACT_EMAIL: { send: async () => { throw new Error("boom"); } } };
  const res = await handleContact(post(JSON.stringify(good), json), failing, deps());
  assert.equal(res.status, 502);
  assert.deepEqual(await res.json(), { ok: false, error: "unavailable" });
});
