# Donjon

![Donjon cover: an orange slime waiting down a torch-lit wireframe corridor](crawler/assets/donjon-cover.png)

A Wizardry-style wireframe dungeon crawler where every monster decision comes from **Jev**, TypeSafe's System One model, instead of hand-tuned heuristics. Talk to monsters, recruit them, and keep them loyal. Details, controls and the itch.io build are in [crawler/README.md](crawler/README.md).

**Setup:** `npm install`, then copy `.env.example` to `.env` and put your TypeSafe API key in it (get one at https://console.typesafe.ai/keys). The key stays on the server and is never sent to the browser.

```bash
npm run crawler              # http://localhost:5174
npm test                     # unit tests (node:test, no API calls)
npm run crawler:scenarios    # scripted encounters against the live API (spends credits)
```

Play it on itch.io: https://aalfalasi.itch.io/donjon. GitHub Actions (`.github/workflows/ci.yml`) tests every push and pull request, and publishes `main` there automatically. Changes are listed in [CHANGELOG.md](CHANGELOG.md).

**Genre Halls** (`npm run crawler`, then http://localhost:5174/genre-halls.html) is a pitch for Undertale-style battles on Donjon's dungeon. Each faction attacks in its own genre (goo rain, chess, shadow, rhythm), and you choose to FIGHT, ACT, SPARE or FLEE. See [crawler/README.md](crawler/README.md#genre-halls-undertale-style-battles).

The earlier gate-guard prototype, The South Gate, lives on the `south-gate` branch.
