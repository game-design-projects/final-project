// Cloudflare Worker for the itch.io build: holds the TypeSafe key so it never ships in the zip.
// Secret (set with `npx wrangler secret put`): TYPESAFE_API_KEY, or OPENROUTER_API_KEY to reach Jev via OpenRouter.
import { handleApi } from "../src/api.js";

export default {
  fetch(request, env) {
    // Fail closed: without the key configured, answer nothing.
    if (!env.TYPESAFE_API_KEY && !env.OPENROUTER_API_KEY)
      return new Response(JSON.stringify({ error: "Server not configured" }), {
        status: 503,
        headers: { "content-type": "application/json", "access-control-allow-origin": "*" },
      });
    return handleApi(request, env);
  },
};
