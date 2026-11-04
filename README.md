# Donjon

![Donjon: a wireframe corridor with a slime waiting down it](docs/donjon-cover.png)

A wireframe dungeon crawler with Undertale-style fights. The dungeon is a real 3D set drawn as glowing line art, and you can talk to the monsters: each one has a personality, feels something about what you do, and may spare you, join you or turn on you.

Donjon is a Godot 4.7 project (GDScript) for the browser, Windows, macOS and Linux. Changes are in [CHANGELOG.md](CHANGELOG.md).

**Docs:** [The game](docs/GAME.md) · [Development](docs/DEVELOPMENT.md) · [Music and voices](docs/AUDIO.md) · [Architecture](docs/ARCHITECTURE.md) · [Personality playtest](docs/PERSONALITY_PLAYTEST.md). Agents working here: start with [AGENTS.md](AGENTS.md).

## Run it

You need [Godot 4.7.2](https://godotengine.org/download). From the project folder:

```bash
godot --headless --path . --import   # once, and again after adding files or assets
godot --path .                       # play
```

No key is needed: without Jev, the monsters think with local rules. Prebuilt builds come out of CI as workflow artifacts, and every `vX.Y.Z` tag becomes a GitHub release.

## Playing

| Where | Keys |
| --- | --- |
| Walking | ↑/W forward · ↓/S back · ←/A and →/D turn · **I** details · **Esc** pause menu |
| Fight menu | ↑/↓ choose · **Enter**, Space or Z pick · **1–4** pick directly · **I** details · **Esc** pause menu |
| Strike bar | **Enter** (or click the picture) when the line crosses the middle |
| Dodge | arrows or WASD |
| Menu pages | ↑/↓ choose · ←/→ change a setting · **Enter** pick · **1–9** pick directly · **Esc** back |

The mouse works too: hover a command to pick it, hover the foe, an ally or the map for details. Touch devices get an on-screen pad.
