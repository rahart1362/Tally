// tally-app.dev on Cloudflare Workers: static pages come from ./site (wrangler.jsonc `assets`);
// this Worker runs only for paths that aren't a static file, which is /api/contact plus
// anything unknown (handed back to the assets binding for the 404 page).
import { EmailMessage } from "cloudflare:email";
import { handleContact } from "./contact.js";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/api/contact") {
      return handleContact(request, env, {
        makeMessage: (from, to, raw) => new EmailMessage(from, to, raw),
        now: () => Date.now(),
        randomId: () => crypto.randomUUID(),
      });
    }
    return env.ASSETS.fetch(request);
  },
};
