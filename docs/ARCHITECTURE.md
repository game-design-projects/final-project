# Donjon 结构

一个游戏、一套界面：3D 这一条线。2D 原版已弃用，见 [AGENTS.md](../AGENTS.md)。

箭头表示**数据往哪流**，不是严格的 DAG：`game ⇄ mind` 是一问一答。

## 模块

| 模块 | 做什么 | 数据从哪来 → 到哪去 |
| --- | --- | --- |
| `menu` | 主菜单、设置、存档页面（暂停菜单复用同一套页面） | → `gameplay`（经 `session` 交请求） |
| `gameplay` | 一局游戏的场景：把 `game` `view` `audio` `mind` 接起来、读输入、暂停、自动存档 | `menu` → 它 → `game` |
| `view` | 3 渲 2 画面：3D 布景（`stage` `dungeon_mesh` `monster_model` `decor`）、战斗层（`overlay`）、小地图（`automap`）、文字框（`hud`）、提示卡和盟友条（`tips`）、触屏（`pad`） | `assets` `flags` → `view` → `game`（玩家输入） |
| `audio` | 声音：合成音效（`sfx` `synth`）、音乐（`music`）、怪物录音和合成嗓音（`voices` `shout`）、总线（`mix`） | `assets` `flags` `game`（事件）→ `audio` |
| `game` | 流程、状态机 | `menu` `view` `audio` `mind` → `game` → `mind` `rules` |
| `mind` | 怪物怎么思考 | `game` `data` → `mind` → `rules` `game`（决定） |
| `rules` | 规则，纯逻辑 | `game` `mind` `data` → `rules` |
| `network manager` | 对外的唯一出口：统一超时、重试、连续失败后暂时离线，失败时调用方回退到本地规则 | `mind` → 它 → `proxy` |

数据与资源：`data`（物种、台词、数值）、`assets`（音乐、字体、语音）、`flags`（启动参数）。
外部：`proxy`（持有密钥）→ Jev LLM。本地语音识别（`native/asr`）和按住说话暂未带回。

## 约定

- 联网和子进程只经 `network manager`；超时和失败回退放在这一处。
- 日志、随机、存储、启动参数是小工具，不画在图里，统一放在 `src/utils/`，由用到的模块直接使用。
- 场景文件（`.tscn`）跟各自模块放在一起，不单设目录。

## 目录

```
src/  menu/  gameplay/  view/  audio/  game/  mind/  rules/  network/  utils/
data/  assets/  proxy/  tools/  docs/
```
