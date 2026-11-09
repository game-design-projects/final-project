# 开场视频：Seedance prompt（issue #56）

这段视频最初是开场过场的**参考**。第三次生成的结果现在就是游戏的开场影片：`tools/intro_video.sh` 把它转成 `assets/video/intro.ogv`，NEW GAME 之后播放（`intro-cg` 开关，`src/menu/intro_cg.gd`），看完后接练习层，由 Wick 教（`docs/GAME.md`）。重新生成之后用同一个脚本替换文件即可。

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

STYLE: 2D hand-drawn line animation in the exact look of @Image1. Wobbly hand-inked WHITE lines about 2px wide on pure black. Every body and object is a solid black silhouette with a thin outline, so it hides whatever is behind it. The background is pure black in every shot, in every room. Walls, floors, ceilings, slabs, windows and every other object are never filled with colour, cream, beige or mint: they stay black with a coloured outline, and only the outline colour changes. No fills, no gradients, no shading, no photoreal lighting. The picture is shown on an old vector monitor: soft phosphor glow around bright lines, very faint horizontal scanlines, dark vignette, crisp chunky pixel edges (a 448x288 image scaled up, not smoothed). Colour exists only as tinted lines: cream stone lines (#e8e2d0), amber torch flames and embers (#ffb347), gold chest and hearts (#ffd27a), mint-teal for the little witch (#8fe8d8). Cute, spooky and a bit wacky, like a Goosebumps cover, never horror, no blood.

POV: first person throughout. The viewer is a person whose face is never seen. Only their two small hands may appear, drawn as black-filled shapes with a white outline, as sleeves with no skin detail. No face, no body, no reflection of the person.

SHOT 1 (0-4s). Black void. The treasure chest from @Image2 sits in the middle, drawn in gold line, a heart-shaped lock on its front. Two small hands, each about a sixth of the frame wide, reach in from the bottom corners and take the lid by its edges. The lid swings up on its hinge until it stands wide open, like a sleepy mouth yawning, and the heart lock gives a slow wink. Inside there is no treasure: the inside is a long corridor in perspective drawn in white lines, the corridor of @Image1, tiny and far away. The corridor lines stretch toward the camera, tugging the view in. A small amber ember (#ffb347) floats up off the hands and stays in frame.

SHOT 2 (4-10s). The camera is pulled into the chest and falls down the corridor, fast and smooth. The corridor comes apart into stone slabs, arched windows, torches, hanging chains and doors, and they slide, flip and re-deal like a deck of cards being shuffled, three times. Each re-deal builds a different corridor on the same black, and only the colour of the white line work changes: cream, then cyan (#8fd3e8), then moss green (#9ed36b), then violet (#b79cf0). The slabs must be seen to detach, slide and flip, not to cross-fade from one room into the next. The amber ember stays with the camera through every shuffle and is never shuffled away. Passing gags drawn like @Image5: a barred arched window with a sleeping moon, a skull in a window that nods at the camera, a bat hanging upside down from a ceiling hook that opens one eye as the camera falls past, a heart banner that flaps. Show at least the skull, the bat and the banner, each small and drawn in outline only.

SHOT 3 (10-15s). The shuffling settles. The camera lands with a small squash and bounce in a straight stone corridor, cream lines, the view of @Image1. The torches on the walls light one at a time down the corridor, whoomph, whoomph, and each flame grows two tiny solid black dot eyes, like the little witch's: no white eyeballs, no pupils, no googly eyes. Each flame turns to look at the camera, leaning toward it. Far down the corridor a very small witch, as in @Image3 (huge pointed hat, short scarf, two tall pill-shaped eyes, no mouth, mint-teal line), comes hopping toward the camera in squashy little hops. She stops, waves, and a small heart pops above her head like @Image4. Hold the final composition for the last 1.5 seconds: centred corridor, torches left and right, the witch in the middle, matching @Image1.

CAMERA: smooth, no shake, no cuts inside a shot, a hard cut between shots.

AUDIO: a slow music-box melody over a soft church-organ drone with a few harpsichord notes, one distant tubular bell at the start of shot 2. Sound effects: a wooden chest creak, a soft whoosh, stone slabs clacking like shuffled cards, a small boing for each hop, a tiny pop for the heart. No voice, no dialogue.

AVOID: any text, letters, captions or logos; any visible face or body of the viewer; photorealism, 3D shading, coloured or beige wall fills, paper or cel-shaded textures, soft coloured vignette blobs, black outlines drawn on light fills, gore, jump scares, extra characters, a second witch, a dragon.
```

## 第一次生成的结果（Dreamina，854×480，60fps，15 秒）

| 镜头 | 结果 |
| --- | --- |
| 1 宝箱（0–4s） | 对。金色线宝箱、爱心锁，箱盖打开，里面是远处的走廊，琥珀色火星升起。手是黑底白边的卡通手，但是托着箱子，箱盖自己开，没有“两只手掀盖” |
| 2 洗牌（4–10s） | 偏了。火星一路跟着，窗、锁链、骷髅窗都出现；但墙被填成米黄、青、绿、蓝绿、紫的色块，带泛黄的暗角和粗黑描边，是另一种卡通上色画风；房间之间是渐变过渡，看不出石板拆开再翻牌；蝙蝠、爱心旗、月亮窗没出现 |
| 3 落地（10–15s） | 对，几乎就是 `keyart.png`。白线黑底，火把长了眼睛，Wick 青色线，从远处蹦近、挥手、头上冒心 |

另外：左上角有 “AI” 水印，分辨率只有 480p；音轨有，没有听内容；镜头之间没有硬切，是连续的。

结论：镜头 1 和 3 可以当参考，镜头 2 是 prompt 没压住的地方。上面的 prompt 已按这次的结果改成第二版：明说“墙永远是黑的，只有线的颜色变”、“石板要看得见拆开翻牌，不要渐变”、“至少出现骷髅、蝙蝠、爱心旗”，并把彩色墙面、纸质 / 赛璐珞质感、彩色暗角、浅色底的黑描边写进 AVOID。水印和分辨率换 720p 以上的无水印档位解决。

### 第二次生成（第二版 prompt，同样 480p）

| 镜头 | 结果 |
| --- | --- |
| 1 宝箱 | 好一半。纯黑底、金色线。但箱盖没有掀开：走廊从箱子正面“透”出来；两只手画得太大，是两坨黑色大手套 |
| 2 洗牌 | 好。背景一直是黑的，线的颜色依次是白、青、绿、紫；奶白色石板飞散再重组，看得见洗牌；火星一路跟着；骷髅、爱心旗、蝙蝠、锁链、月亮窗都出现了。还有毛病：飞散的石板是奶白实心块，绿色那格是一整块薄荷绿实心的拱窗，骷髅太大，蝙蝠是躺着的不是倒挂 |
| 3 落地 | 好，白线黑底，Wick 青色线，蹦近、挥手、冒心。火把的眼睛变成了带眼白的“googly eyes”，游戏里是火苗上两颗小黑点 |

没看到水印；分辨率仍是 854×480。

第三版 prompt 针对这几处：所有物体“黑底加彩色描边，不填色”；手缩小、从两个下角抓盒盖边，盖子绕铰链完全立起；火把眼睛写成“两颗实心黑点，不要眼白、不要瞳孔”；蝙蝠“倒挂在天花板钩子上”；骷髅、蝙蝠、旗都“小一点，只画轮廓”。

### 第三次生成（第三版 prompt，同样 480p）

| 镜头 | 结果 |
| --- | --- |
| 1 宝箱 | 对。手只剩白色轮廓，箱盖绕铰链完全立起，里面是走廊，火星升起 |
| 2 洗牌 | 基本对。黑底，线色依次是青、绿、紫，没有实心墙面了；窗、锁链、倒挂的蝙蝠、爱心旗、骷髅都出现了。剩下的：骷髅、蝙蝠、旗是单色实心块，不是“黑底加描边”；“拆开翻牌”变成了镜头翻滚，只有青色那段能看出翻动，没有石板飞散 |
| 3 落地 | 对。火把的眼睛是两颗小黑点，和游戏一致；Wick 青线、蹦近、挥手、冒心。约 11 秒时远处地面有一小团白色涂鸦，是生成的杂点 |

结论：第三版可以当给队友看的参考，不再为它改 prompt。真要接进游戏时只当分镜用：镜头 1 和 2 重画成几张定格（#56 的 “a few drawn frames”），镜头 3 由 `opening.gd` 来做。如果还要再出一版，只改一处：把 “each small and drawn in outline only” 换成 “black body with a coloured outline, exactly like @Image5”。

## 用法和取舍

- **时长**：15 秒在 Seedance 2.0 和 2.5 都能一次出（2.5 单次最长 30 秒）。想要更长就把第 2 镜拆成两段分别生成再剪。
- **一致性**：Wick 和宝箱靠 `@Image` 锁形状；换参考图要整套重生成，别在两次生成之间换图。
- **文字**：视频不出字。开场字幕（`premise.line` 和 “It only opens for someone who is not alone.”）由引擎用 PressStart2P 叠，AI 视频生成不出可读的像素字。
- **和引擎开场的衔接**：引擎的开场（`opening.gif`）从一条空走廊和标题字开始，Wick 才从远处蹦来递心，所以视频第 3 镜和它是同一件事。真接进游戏时，视频只用到第 2 镜落地、火把点亮为止，之后交给 `opening.gd`。视频的最后一帧（Wick 已在走廊中央）是 `keyart.png` 的构图，只给队友看用。
- **还没定的**：玩家是谁（视频里的手要不要换成确定的角色）、Hoard 是不是箱子的主人（现在只靠箱子的爱心锁暗示）、被吸进去之后“五层以下才是 Last Door”要不要在视频里交代（现在不交代，留给文字）。
- **生成后用到游戏里**：视频只做过场参考。真要放进游戏，镜头 1 和 2 做成几张手绘定格（#56 的 “a few drawn frames”），镜头 3 用现有的 `opening.gd`，不引入视频播放。
