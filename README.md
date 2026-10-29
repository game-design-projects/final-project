# Donjon

![Donjon cover: an orange slime waiting down a torch-lit wireframe corridor](crawler/assets/donjon-cover.png)

A Wizardry-style wireframe dungeon crawler where every monster decision comes from **Jev**, TypeSafe's System One model, instead of hand-tuned heuristics. Talk to monsters, recruit them, and keep them loyal. Details, controls, the Jev API Worker and the browser build are in [crawler/README.md](crawler/README.md).

**Setup:** `npm install`, then copy `.env.example` to `.env` and put your TypeSafe API key in it (get one at https://console.typesafe.ai/keys). The key stays on the server and is never sent to the browser.

```bash
npm run crawler              # http://localhost:5174
npm test                     # unit tests (node:test, no API calls)
npm run crawler:scenarios    # scripted encounters against the live API (spends credits)
```

Builds away from the local server reach Jev through a Cloudflare Worker that holds the key, https://donjon-api.lishuyustevenli.workers.dev ([crawler/README.md](crawler/README.md#the-jev-api-cloudflare-worker)). GitHub Actions tests every push and pull request (`.github/workflows/ci.yml`) and deploys that Worker from `main` (`.github/workflows/worker.yml`, with a token scoped to that one Worker). Nothing publishes to itch.io any more: the final ships as a native build, and the week-4 browser build stays at https://aalfalasi.itch.io/donjon. Changes are listed in [CHANGELOG.md](CHANGELOG.md).

**Genre Halls** (`npm run crawler`, then http://localhost:5174/genre-halls.html) is a pitch for Undertale-style battles on Donjon's dungeon. Each faction attacks in its own genre (goo rain, chess, shadow, rhythm), and you choose to FIGHT, ACT, SPARE or FLEE. See [crawler/README.md](crawler/README.md#genre-halls-undertale-style-battles).

The earlier gate-guard prototype, The South Gate, lives on the `south-gate` branch.
