# TODO

- [ ] **Give the Jev API Worker its key.** Until then https://donjon-api.lishuyustevenli.workers.dev answers 503 to every request, so builds that use it get no monster decisions. Make an OpenRouter key with a credit limit (openrouter.ai/settings/keys), then, in your own terminal: `cd crawler/proxy && npx wrangler secret put OPENROUTER_API_KEY`. The Worker keeps it across deploys, and CI's smoke test stops warning once it answers 400 instead of 503.
