# 开场视频：Seedance prompt（issue #56）

这段视频是开场过场的**参考**，不是成品：Steven 用它给队友看“被拉进 donjon 领域”大概是什么感觉。游戏里真正的开场由引擎画（`src/view/opening.gd`，`wick` 开关），视频里的文字、画面比例和细节都以引擎为准。

## 它要讲清楚的三件事（来自 #56）

1. **怎么进来的**：玩家往一个箱子里看，被吸进去（Pear 的 Gungeon 式时空扭曲，Abdulla 的传送门，Elden Ring 的陷阱宝箱）。箱子就是 `props` 图集里那只带爱心锁的宝箱，也就是 `premise.line` 里那个 Hoard。
2. **为什么每局不一样**：墙、火把、窗、门像一副牌一样被拆开、洗乱、重新发出来，每洗一次换一套墙色（`palette.gd` 的 BONE CRYPT → DROWNED HALLS → MOSS DEEP → VIOLET CATACOMB）。
3. **为什么每次回来更强**：玩家手里有一小团琥珀色的火星（`legacy` 的 embers），洗牌时它一直跟着，不被洗掉。

结尾落在游戏真实的开场构图上：笔直的走廊、两侧火把、远处一个很小的女巫（Wick）蹦过来递一颗心（`docs/art/game/opening.gif`、`assets/art/keyart.png`）。

**玩家是谁还没定，所以视频里不出现玩家**：第一人称，只露出一双小小的手（黑色填充、白色描边）。定了角色再补一版。

调性：Goosebumps，阴森里带点滑稽，不是恐怖；测试者说美术“cute”。所以箱子会打哈欠，路过的蝙蝠睁一只眼，骷髅点头，全是游戏里已经有的 `decor` 素材。

## 画面从哪来（全部取自仓库）

| 项 | 取值 | 出处 |
| --- | --- | --- |
| 线条 | 白色手绘线，约 2px，微微抖；身体内部实心黑，会挡住身后的东西 | `docs/ART.md`、`shaders/figure.gdshader` |
| 后期 | 老矢量显示器：线条有磷光泛光、淡横向扫描线、暗角、像素边缘锐利，画面本身是 448×288 放大 | `shaders/postfx.gdshader` |
| 颜色 | 只有线条带色，没有色块填充：墙线 `#e8e2d0`（BONE CRYPT），火把和火星 `#ffb347`，宝箱和爱心 `#ffd27a`（MERCY），Wick `#8fe8d8`（`friends.json`） | `palette.gd`、`friends.json` |
| 换墙色 | `#8fd3e8` → `#9ed36b` → `#b79cf0` | `palette.gd` RUNS |
| 运动 | 落地压扁、蹦着走；火把有眼睛，会朝你弯 | `docs/ART.md`、`shaders/flame_drawn.gdshader` |
| 声音 | 巴洛克地牢风：羽管键琴、教堂管风琴、八音盒、管钟（D 小调，慢） | `docs/AUDIO.md` |
| 字体 | PressStart2P / VT323；视频里不生成文字，字幕由引擎叠 | `assets/fonts/` |

## 参考图（`docs/intro/refs/`，由 `tools/intro_refs.py` 从游戏图集裁出）

| 文件 | 用在 | 内容 |
| --- | --- | --- |
| `1_corridor_keyart.png` | 画风 + 最后一帧 | 走廊、两侧火把、Wick |
| `2_chest.png` | 第 1 镜 | 带爱心锁的宝箱，金色线 |
| `3_wick_idle.png` | 第 3 镜 | Wick 站立，青色线 |
| `4_wick_heart.png` | 第 3 镜 | Wick 笑眼加爱心 |
| `5_wall_things.png` | 第 2 镜 | 月亮铁窗、点头骷髅、倒挂蝙蝠、爱心旗 |

Seedance 2.x 的参考图模式里按顺序叫 `@Image1`…`@Image5`；上传顺序必须和上表一致。首尾帧模式不能同时带参考图：那就只上传 `2_chest.png` 做首帧、`1_corridor_keyart.png` 做尾帧，把下面 prompt 里的 `@Image…` 换成文字描述。

## Prompt（英文，直接粘贴）

```
15 seconds, 3 shots, 16:9 (keep everything important inside the centre 14:9), 24fps.

STYLE: 2D hand-drawn line animation in the exact look of @Image1. Wobbly hand-inked WHITE lines about 2px wide on pure black. Every body and object is a solid black silhouette with a thin outline, so it hides whatever is behind it. No fills, no gradients, no shading, no photoreal lighting. The picture is shown on an old vector monitor: soft phosphor glow around bright lines, very faint horizontal scanlines, dark vignette, crisp chunky pixel edges (a 448x288 image scaled up, not smoothed). Colour exists only as tinted lines: cream stone lines (#e8e2d0), amber torch flames and embers (#ffb347), gold chest and hearts (#ffd27a), mint-teal for the little witch (#8fe8d8). Cute, spooky and a bit wacky, like a Goosebumps cover, never horror, no blood.

POV: first person throughout. The viewer is a person whose face is never seen. Only their two small hands may appear, drawn as black-filled shapes with a white outline, as sleeves with no skin detail. No face, no body, no reflection of the person.

SHOT 1 (0-4s). Black void. The treasure chest from @Image2 sits in the middle, drawn in gold line, a heart-shaped lock on its front. Two small hands reach in from the bottom of the frame and lift the lid. The lid yawns open like a sleepy mouth and the heart lock gives a slow wink. Inside there is no treasure: the inside is a long corridor in perspective drawn in white lines, the corridor of @Image1, tiny and far away. The corridor lines stretch toward the camera, tugging the view in. A small amber ember (#ffb347) floats up off the hands and stays in frame.

SHOT 2 (4-10s). The camera is pulled into the chest and falls down the corridor, fast and smooth. The corridor comes apart into stone slabs, arched windows, torches, hanging chains and doors, and they slide, flip and re-deal like a deck of cards being shuffled, three times. Each re-deal builds a different corridor and changes the line colour of the stone: cream, then cyan (#8fd3e8), then moss green (#9ed36b), then violet (#b79cf0). The amber ember stays with the camera through every shuffle and is never shuffled away. Passing gags drawn like @Image5: a barred arched window with a sleeping moon, a skull in a window that nods at the camera, a hanging bat that opens one eye as the camera falls past, a heart banner that flaps.

SHOT 3 (10-15s). The shuffling settles. The camera lands with a small squash and bounce in a straight stone corridor, cream lines, the view of @Image1. The torches on the walls light one at a time down the corridor, whoomph, whoomph, and each flame grows two small eyes and turns to look at the camera, leaning toward it. Far down the corridor a very small witch, as in @Image3 (huge pointed hat, short scarf, two tall pill-shaped eyes, no mouth, mint-teal line), comes hopping toward the camera in squashy little hops. She stops, waves, and a small heart pops above her head like @Image4. Hold the final composition for the last 1.5 seconds: centred corridor, torches left and right, the witch in the middle, matching @Image1.

CAMERA: smooth, no shake, no cuts inside a shot, a hard cut between shots.

AUDIO: a slow music-box melody over a soft church-organ drone with a few harpsichord notes, one distant tubular bell at the start of shot 2. Sound effects: a wooden chest creak, a soft whoosh, stone slabs clacking like shuffled cards, a small boing for each hop, a tiny pop for the heart. No voice, no dialogue.

AVOID: any text, letters, captions or logos; any visible face or body of the viewer; photorealism, 3D shading, colour fills, gore, jump scares, extra characters, a second witch, a dragon.
```

## 用法和取舍

- **时长**：15 秒在 Seedance 2.0 和 2.5 都能一次出（2.5 单次最长 30 秒）。想要更长就把第 2 镜拆成两段分别生成再剪。
- **一致性**：Wick 和宝箱靠 `@Image` 锁形状；换参考图要整套重生成，别在两次生成之间换图。
- **文字**：视频不出字。开场字幕（`premise.line` 和 “It only opens for someone who is not alone.”）由引擎用 PressStart2P 叠，AI 视频生成不出可读的像素字。
- **和引擎开场的衔接**：引擎的开场（`opening.gif`）从一条空走廊和标题字开始，Wick 才从远处蹦来递心，所以视频第 3 镜和它是同一件事。真接进游戏时，视频只用到第 2 镜落地、火把点亮为止，之后交给 `opening.gd`。视频的最后一帧（Wick 已在走廊中央）是 `keyart.png` 的构图，只给队友看用。
- **还没定的**：玩家是谁（视频里的手要不要换成确定的角色）、Hoard 是不是箱子的主人（现在只靠箱子的爱心锁暗示）、被吸进去之后“五层以下才是 Last Door”要不要在视频里交代（现在不交代，留给文字）。
- **生成后用到游戏里**：视频只做过场参考。真要放进游戏，镜头 1 和 2 做成几张手绘定格（#56 的 “a few drawn frames”），镜头 3 用现有的 `opening.gd`，不引入视频播放。
