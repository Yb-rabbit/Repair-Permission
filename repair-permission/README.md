# Repair Permission

3 小时 Jam 版终端微恐怖。玩家是夜班技师 TECH-077，面前两台机器：OLD（1979 年绿字终端，延迟 3 秒，全大写，记录一切）和 NEW（现代助手，秒回，会替你做决定）。没有 jump scare，恐怖只来自信息错位。

## 运行

Godot 4.7 打开项目，`F5`。主场景 `res://Main.tscn`，脚本 `res://game.gd`，数据 `res://script_data.json`。

## 结构

```text
res://
├── Main.tscn          Control 场景（双 RichTextLabel / 3 ProgressBar / LineEdit / CRT 空槽 / EndStatus / FinalLine / RestartHint / Popups 图层 / 7 Timer）
├── game.gd            全部逻辑
├── audio.gd           房间底噪 / 双终端待机 / 一次性音效 / ACCEPT 低频嗡鸣
├── audio/             8 个程序生成 WAV（无外部版权素材）
├── popup.gd           可拖动 / 可关闭 / 可确认的提示弹窗
├── script_data.json   命令表、乱输入池、彩蛋、三个结局
├── tools/smoke_test.gd
├── tools/audio_probe.gd
├── tools/generate_audio.py
└── _legacy/           v1 实现与旧脚本（归档，不参与运行）
```

CRT 覆盖层是 `Main/CRT`（颜色 alpha 0、鼠标忽略），拿到 `crt.gdshader` 后新建 ShaderMaterial 挂上去即可。弹窗挂在 `Main/Popups`（CanvasLayer layer 10）上，永远画在 CRT 与终端之上。

## 语言与字体

运行时全部界面文案（终端输出、输入提示、值班手册弹窗、按钮与工具提示）均为英文，对白文本集中在 `script_data.json`，界面固定文案在 `game.gd` / `popup.gd`。

文本采用双轨：中文设计正典在 `story_bible.md`，英文对白 / 结局运行文本集中在 `script_data.json`（开机流与 UI 固定文案仍在 `game.gd` / `popup.gd`）。两者冲突时，玩家实际看到的逐字文本以代码与 `script_data.json` 为准，设计解释以 `story_bible.md` 为准。

字体统一使用项目根目录的 `WENQUANYIDIANZHENSONGTI.TTF`（文泉驿点阵宋体），并通过 `ui_font.tres`（`FontVariation`）统一增加字间距（`spacing_glyph = 2`、`spacing_space = 2`）。`project.godot` 的 `gui/theme/custom_font` 指向 `ui_font.tres` 作为全局默认字体，`game.gd` 的 `UI_FONT` 与 `popup.gd` 的 `UI_FONT` 再对 RichTextLabel / LineEdit / 弹窗做显式覆盖。

## 命令

| 命令 | 作用 |
| --- | --- |
| `LOGIN 077` | 登录。OLD 回 `ONE TERMINAL` |
| `HELP` / `STATUS` / `LOG` | 教学 / 状态 / 1979 年日志 |
| `MANUAL` | 重新弹出已经看过的值班手册页面（不剧透未解锁内容） |
| `UNDO` | NEW 说撤销成功，OLD 说没这条命令 |
| `PUMP 3` | 看封条 |
| `PUMP 3 --ISOLATE` | 走 OLD 的机械隔离 |
| `PUMP 3 --ACCEPT-NEW` | 接受 NEW 的远程修复；隐藏值 +2 |
| `SCAN` | 慢扫描（只是台词） |
| `SCAN /FULL` | 15 秒进度条 + 9 行文件系统流；约 74% 卡 99%，约 87% 回落到 97%，再走到 100%；NEW 中途插话两次 |
| `LS /VOID` / `PS` / `CAT /VOID/TECH-077` | 隐藏分区、进程、文本日志 |
| `KILL 077` | 杀掉进程；之后 NEW 的 `/VOID` 变成 0 items；开启 60 秒无输入窗口 |
| `ID` | 房间里有几个人 |
| `FORMAT /VOID` | 结局 A（先逐条回放你的全部输入；restore loop 后淡出至半透明黑，显示 `SHIFT ENDED` / 重开提示，无叙事终行） |
| `SHUTDOWN --VERIFY` | 结局 B（同样先回放；播完后淡出至半透明黑，显示 `SHIFT ENDED` / 重开提示） |
| `SET DATE 2038-01-19` | 结局 C（也可输入命令 `SET DATE 2038-1-19` / `SET DATE 38-01-19`；需先完成 `SCAN /FULL`） |
| `SET DATE 2000-01-01` | 彩蛋：`NOTHING HAPPENED.` / `THAT WAS THE POINT.`（也接受 `2000-1-1` / `00-01-01`） |
| `SET DATE 1979-11-03` | 彩蛋：OLD 的上电日志（也接受 `1979-11-3` / `79-11-03`） |

输入匹配三层：精确 → `begins_with` 补全（例如 `PUMP` → `PUMP 3`，NEW 代跑、OLD 纠错）→ 完全不匹配走气氛回复；乱输入第 3 次触发 OLD 彩蛋。

三个结局都要求先完成 `SCAN /FULL`。A / B 是明确的收场命令，永远优先；C 是独立的第三条路线，不会在 A / B 播放完后接管。C 有两个入口：`SET DATE 2038-*`，或 `KILL 077` 后连续 60 秒不输入任何命令。KILL 的静默窗口会被任意一次真实输入取消，所以 `KILL 077 → LS /VOID` 仍然安全。

A / B 为 0.9 秒淡出至半透明黑（仍能隐约看到终端），C 为 0.9 秒淡出至全黑；淡出后再等 0.25 秒显示 `SHIFT ENDED` 与 `PRESS R TO RESTART`。`SHIFT ENDED` 是 UI 状态，不属于结局叙事文本；A 仍然没有叙事终行。

开局输入框会预填 `LOGIN` 并全选，直接按 Enter 就会补全为 `LOGIN 077`（对应 NEW 的 “I already filled in half the login”）。

## 提示弹窗（值班手册）

右上角浮窗，推玩家往前走，不影响输入（弹窗开着也能继续敲命令）：

| 触发 | 内容 |
| --- | --- |
| 开局 1.2 秒 | 值班手册 01：目标、命令可自动补全、`MANUAL` / `ID`、弹窗操作说明 |
| `LOGIN 077` | 值班手册 02：`LOG` 与下一步 `PUMP 3` |
| `PUMP 3` | 值班手册 03：`--ISOLATE` / `--ACCEPT-NEW` 两条路，以及下一步 `SCAN /FULL` |
| `SCAN /FULL` 扫完 | 值班手册 04：`LS /VOID`、`PS`、`CAT /VOID/TECH-077`；随后 06：32 位上限与 `2038-01-19` 提示 |
| `CAT /VOID/TECH-077` | 值班手册 05：`KILL 077` 与两种收场命令 |

操作：拖标题栏移动位置（自动夹在窗口内）、点右上 `×` 或按 `ESC` 关闭、点「Got it」确认。每条只弹一次，多个提示排队依次出现，进入结局时全部清空。

输入 `MANUAL` 会按首次出现的顺序重新弹出**已经看过**的页面（未解锁的页面不会提前显示）；它会和普通命令一样得到 OLD / NEW 两边的回复。

顺序保护：如果玩家在扫描前就输入 `CAT /VOID/TECH-077`，会先把手册 04 排进队列，再排 05，避免跳过隐藏分区说明。

新增提示：在 `game.gd:_hint_for()` 里加一个 `match` 分支调用 `_hint("唯一id", "标题", "BBCode 正文")` 即可。

## 声音

A 档最小声音层：没有旋律 BGM，只有“房间 + 两台机器”的环境声。全部素材由 `tools/generate_audio.py` 用 Python 标准库合成，44.1 kHz / 16-bit / 立体声，循环文件首尾已交叉淡化。

| 层 | 文件 | 默认音量 | 行为 |
| --- | --- | --- | --- |
| 房间底噪 | `audio/room_tone.wav` | -17 dB | 开局持续；黑屏时略降 |
| OLD 待机 | `audio/old_idle.wav` | -21 dB | 50 Hz 嗡鸣 + 风扇 + 偶发继电器/走纸 |
| NEW 待机 | `audio/new_idle.wav` | -24 dB | 干净高频气流，开机完成后淡入 |
| ACCEPT 低频 | `audio/tension_hum.wav` | -21 dB | `PUMP 3 --ACCEPT-NEW` 后淡入，`SCAN /FULL` 开始时淡出 |
| OLD 打印 | `audio/old_print.wav` | -16 dB / 暗行 -25 dB | 每次 OLD 输出一行，4 个播放器轮换，随机微调音高 |
| 回车继电器 | `audio/old_relay.wav` | -15 dB | 每次真实输入 |
| NEW 提示 | `audio/new_tick.wav` | -22 dB | 每次 NEW 发言（打字） |
| NEW 双音 | `audio/new_chime.wav` | -14 dB | 登录成功 / ACCEPT-NEW |

`KILL 077` 后 NEW 待机会淡出，任意真实输入会淡入恢复；结局开始时收掉 ACCEPT 嗡鸣，黑屏降下 NEW/房间层，结局播完 4 秒内全部淡出。弹窗的 `connected.wav` / `disconnected.wav` 仍保留，但音量已从 -4 dB 降到 -10 dB，不再压过环境层。

重新生成素材：`python tools/generate_audio.py`。Godot 首次打开项目会自动导入 `audio/*.wav`；如果直接跑 headless 测试且出现 “no resource loaders”，先执行一次 `godot --headless --import --path .`。

## 调参

`game.gd` 里：`scan_duration`（默认 15 秒）、`END_DIM_ALPHA`（A/B 半透明黑的黑度，默认 0.75）、`END_FADE_TIME`（0.9 秒）、`END_HINT_DELAY`（0.25 秒）。
`Main.tscn` 里：`BootTimer.wait_time`（0.25）、`OldTimer.wait_time`（默认 3 秒）、`ScanTimer.wait_time`（0.1）、`ReplayTimer.wait_time`（0.25）、`EndTimer.wait_time`（1.4）、`InheritTimer.wait_time`（60 秒）。
`popup.gd` 里：`WIDTH`（弹窗宽度 380）、`EDGE`（贴边留白 8）；出现位置在 `open()` 里计算（右上角，按队列层叠 26px）；`SFX_VOLUME_DB`（弹窗音效音量，默认 -10 dB），音源固定为根目录的 `connected.wav` / `disconnected.wav`。

## 冒烟测试

```text
godot --headless --path . --script res://tools/smoke_test.gd
```

结果写入 `smoke_result.txt`，覆盖登录预填（Enter 信号）、命令表加载、三层匹配、提示链内容（LOG / MANUAL / ID / SCAN /FULL）、CAT 顺序保护、乱输入彩蛋、隐藏值、扫描期输入锁、扫描流与 99%→97% 回退、弹窗（出现 / 排队 / 拖拽 / 确认关闭 / 结局清空 / 音效）、A/B 回放、A 的 restore loop / 无 NEW 收尾 / 淡出半透明黑 / 无叙事终行 / 结束卡、B 的淡出半透明黑与结束卡、C 的扫描门槛 / 直接日期入口 / KILL 静默入口 / 输入取消 / A/B 优先 / 时钟回绕 / pre-replay 台词 / `[PATCH]` 回放 / 淡出全黑 / `PATCH-Y2KW v2` 终行 / 结束卡 / R 重置提示、两个 SET DATE 彩蛋及其短格式，以及声音层的节点/循环/状态（当前 97/97 通过）。

只检查声音节点与循环参数（不实际发声）：

```text
godot --headless --path . --script res://tools/audio_probe.gd
```

结果写入 `audio_probe.txt`，包含 4 个循环层的 `playing` / `loop_mode` / `loop_end` / 长度，以及 ACCEPT、SCAN、KILL 的状态切换。

## 已知取舍

- A / B / C 都只要求 `SCAN /FULL` 完成，不要求玩家读过手册页；如果扫描前输入 `FORMAT /VOID` / `SHUTDOWN --VERIFY`，OLD 会回 `UNKNOWN PARTITION.`。手册页只保证 04 → 05 的顺序（扫描前触发 `CAT` 会先排 04）。
- A 结局是 restore loop：`FORMAT /VOID` 回放后重启到 `PLEASE LOG IN`，再淡出到半透明黑并显示 `SHIFT ENDED` / `PRESS R TO RESTART`，没有叙事终行；NEW 的两句结局收尾台词已删除，但命令确认仍保留。
- B 结局淡出至半透明黑，保留“机器还亮着”的隐约轮廓，同时出现 `SHIFT ENDED` / `PRESS R TO RESTART`。
- C 的 KILL 静默窗口是 60 秒，任何真实输入都会取消；它不会在 A / B 结束后被重新启动或接管。C 的 pre-replay 台词在 `script_data.json` 的 `inherit_intro`，回放后的收尾与终行在 `endings.inherit`；计时器是 `Main/InheritTimer`；全黑淡出后显示 `SHIFT ENDED` / `PRESS R TO RESTART`，随后是 `PATCH-Y2KW v2` 终行。
- 左上角铭牌改成了 `1999`，但剧情文本里仍保留 `YEAR 1979`、`LOG 11-03-1979`、`SEALED 1979`、`UPTIME 46Y`（`PS` 的「年份一直是错的」正是靠这些数字成立）。要全局统一成 1999，需要同时改 `boot.old`、`LOG`、`PUMP 3`、彩蛋、三个结局和 `PS` 的 `UPTIME`。
- 弹窗不暂停游戏、不抢输入焦点，所以开着弹窗也能继续敲命令；按钮与面板都不拿键盘焦点。
- 声音只有 A 档环境层（见「声音」），没有旋律 BGM、没有独立音量设置/静音键；素材为程序合成，适合 Jam 原型，正式版可替换为录制素材。
- 没有存档、导出配置。
