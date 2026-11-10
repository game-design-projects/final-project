# Donjon

## 哪份代码才是游戏

- **游戏只有 3D 这一条线**：Genre Halls，0.6.0 重写（`0acd6ef`）后就是现在的 `src/`。结构见 `docs/ARCHITECTURE.md`。
- **2D 原版 Donjon 已弃用**：2D 做不出丝滑，所以改做 3D。它留在 `0acd6ef` 之前的历史里，只是历史：
  - 路径：`src/ui/`、`src/game/`、`src/jev/`、`src/rules/tutorial.gd`、`src/rules/achievements.gd`、`src/audio/asr.gd`、`native/asr/` 等。
  - 不在它上面加功能，不从它移植代码。同类功能可以参考设计思路，然后在当前架构上重新做。
  - 反例：ASR 当年被加到了 2D 版上，3D 版从没用过。
- **查“重写丢了什么”时**，对照重写前的 3D 线（`017b551` 的 `src/genre/`、`src/menu/` 和它们加载的文件），不对照 2D 版。

## 试玩

- 试玩的版本是 `017b551`（0.5.3 加性格切片，重写之前）。反馈汇总在 issue #41。

## 不要改回去

- 走廊透视以当前版本为准（`stage.gd` 的 FOV 68、眼高 0.85，`dungeon_mesh.gd` 的墙高 1.7）：用户确认新版才是对的，因为旧版的墙不是正方形（旧版格宽 2.0、墙高 2.2；现在格宽 2.0、墙高 1.7）。
- 战斗结束不弹 CONTINUE 界面，这是有意改的。

## 提交与推送

- 修改本文件或仓库里的其他文件后，需要时直接 commit 并 push 到当前分支，**不用先征求许可**。
- push 前先 `git pull --rebase`；冲突时停下来汇报，不 force push。
