# Donjon 结构

一个游戏、一套界面：3D 这一条线。2D 原版已弃用，见 [AGENTS.md](../AGENTS.md)。

箭头表示**数据往哪流**，不是严格的 DAG：`game ⇄ mind` 是一问一答。

## 模块

| 模块 | 做什么 | 数据从哪来 → 到哪去 |
| --- | --- | --- |
| `menu` | 主菜单、设置、存档页面（暂停菜单复用同一套页面）、NEW GAME 之后的开场影片（`intro_cg`） | → `gameplay`（经 `session` 交请求） |
| `gameplay` | 一局游戏的场景：把 `game` `view` `audio` `mind` 接起来、读输入、暂停、自动存档 | `menu` → 它 → `game` |
| `view` | 3 渲 2 画面：3D 布景（`stage` `dungeon_mesh`；手绘的 `figure` `figure_anim` `wall_art` `opening`，墙饰的位置在 `decor`）、战斗层（`overlay`，手绘的怪物在 `battle_art`）、小地图（`automap`）、文字框（`hud`）、走路停下来时画面中央的选择卡和事件小动画（`choice_popup` `vignette`）、提示卡和盟友条（`tips`）、触屏（`pad`） | `assets` `flags` → `view` → `game`（玩家输入） |
| `audio` | 声音：合成音效（`sfx` `synth`）、音乐（`music`）、怪物录音和合成嗓音（`voices` `shout`）、总线（`mix`） | `assets` `flags` `game`（事件）→ `audio` |
| `game` | 流程、状态机 | `menu` `view` `audio` `mind` → `game` → `mind` `rules` |
| `mind` | 怪物怎么思考；`Minds.create` 给出的每个 mind 都包在 `safe_mind` 里，答案在这里校验后才交给 `game` | `game` `data` → `mind` → `rules` `game`（决定） |
| `rules` | 规则，纯逻辑 | `game` `mind` `data` → `rules` |
| `network manager` | 对外的唯一出口：统一超时、重试、连续失败后暂时离线，失败时调用方回退到本地规则 | `mind` → 它 → `proxy` |

数据与资源：`data`（物种、种类、台词、数值）、`assets`（音乐、字体、语音、手绘图集）、`flags`（启动参数）。
外部：`proxy`（持有密钥）→ Jev LLM。本地语音识别（`native/asr`）和按住说话暂未带回。

`game` 里的阶段都在 `game/stages/`，一张转移表（`transitions.gd`）管住能从哪到哪，每个阶段算战斗还是行走（`FIGHT` / `WALK`，选指令的是 `PICKING`，选择本身就是全部内容、要摆到画面中央的是 `DECIDING`）也只在这里写，画面和提示从这里读，事件的字段在 `events.gd` 里校验。小游戏和攻击一个文件一个，在 `rules/minigames/`：`spawn` 每帧加危险格，可选的 `begin` 在第一帧前摆柱子、灯笼或镜像操作，自己的状态放 `run.mem`，危险格能带的画面标记写在 `dodge_run.gd` 开头；地图生成器也是一个文件一个，在 `rules/maps/`。小地图画什么由两份数据定：`State.seen`（镜头看到过的格子）和 `State.charted`（没看到、但从地图或直觉得知布局的格子，`rules/chart.gd`）；`view/automap.gd` 一个节点两种画法，角落的窗口和 `full` 的全图。怪物 = 物种 + 种类：物种（`data/species.json`）定氏族、行为、口味、台词和当朋友时的护符，种类（`data/kinds.json`，`rules/kinds.gd`）定外形、颜色、血量、攻击和走法，每层五种、层间不重复；冠军不属于种类，轮流用本层五种的攻击。视图按 `Sprites.look_of` 取种类的图，没有就用物种的。跨局留下的东西（成就、余烬、加成、读过的墙上文字）存在 `menu/progress.gd`，由 `gameplay` 交给 `game`；`game` 只发事件（`trophy`、`run_closed`、`found` 里的 `lore`），不碰存储。

## 约定

- 联网和子进程只经 `network manager`；超时和失败回退放在这一处。
- 故障策略只在 `utils/fault.gd` 一处：debug 版快速失败，导出版容错。导出版里 GDScript 出错不中断也不记日志（缺的 key 读成 null，函数照常跑完，`assert` 不执行），所以会出错的模块（联网的 mind 是第一个）在边界上校验答案：不合格就 `Fault.report`（debug 版在这里停下），`Fault.tolerant()` 为真时换成备用答案继续。新增这类边界时照 `mind/safe_mind.gd` 写，不在调用处各自判空。
- 日志、随机、存储、启动参数是小工具，不画在图里，统一放在 `src/utils/`，由用到的模块直接使用。
- 场景文件（`.tscn`）跟各自模块放在一起，不单设目录。
- 新功能默认就是游戏的一部分，不加开关；需要和旧行为对照的才进 `utils/flags.gd` 的 `FEATURES`（默认开，`no-<name>` 单独关掉；`OPT_IN` 里的实验功能例外，不点名不开）。
- 数值和文本放 `data/*.json`，由 `rules/content.gd` 读。

## 目录

```
src/  menu/  gameplay/  view/  audio/  game/  mind/  rules/  network/  utils/
data/  assets/  proxy/  tools/  docs/
```

## 手绘美术

图集由 `tools/art/process.py` 从 Codex 出的表切成，`data/sprites.json` 记录每一帧的位置，`view/sprites.gd` 读它。怪物在走路和战斗里用同一套图：`figure_anim.gd` 决定此刻显示哪个动作的哪一帧，`figure.gd` 把它放进 3D，`battle_art.gd` 把它画进战斗层。

世界“温度”（`rules/warmth.gd`）不存盘，从 tally、butchered、left_behind、meals 推导，所以旧存档自动有温度，重试战斗也会回退。`stage` 每帧读它，改墙缝强度，等级变化时重建墙饰；`rules/moods.gd` 决定每张脸显示什么。设计见 [ART.md](ART.md)。
