# Donjon

A Wizardry-style wireframe dungeon crawler where every monster decision comes from **Jev**, TypeSafe's System One model, instead of hand-tuned heuristics. Talk to monsters, recruit them, and keep them loyal. Details, controls and the itch.io build are in [crawler/README.md](crawler/README.md).

**Setup:** `npm install`, then copy `.env.example` to `.env` and put your TypeSafe API key in it (get one at https://console.typesafe.ai/keys). The key stays on the server and is never sent to the browser.

```bash
npm run crawler              # http://localhost:5174
npm run crawler:scenarios    # scripted encounters against the live API
```

The earlier gate-guard prototype, The South Gate, lives on the `south-gate` branch.
