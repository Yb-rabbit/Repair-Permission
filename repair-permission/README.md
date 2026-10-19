# Repair Permission

3 小时 Jam 版终端微恐怖。玩家是夜班技师 TECH-077，面前两台机器：OLD（1979 年绿字终端，延迟随状态在 2–8 秒间变化，全大写，记录一切）和 NEW（现代助手，秒回，会替你做决定）。没有 jump scare，恐怖只来自信息错位。

## 运行

Godot 4.7 打开项目，`F5`。主场景 `res://Main.tscn`，脚本 `res://game.gd`，数据 `res://script_data.json`。

## 结构

```text
res://
├── Main.tscn          Control 场景（双 RichTextLabel / 3 ProgressBar / LineEdit / CRT 空槽 / ScanBand / Glitch / EndStatus / EndTag / FinalLine / RestartHint / Popups 图层 / 7 Timer）
├── game.gd            全部逻辑
├── audio.gd           房间底噪 / 双终端待机 / 一次性音效 / ACCEPT 低频嗡鸣
├── audio/             8 个程序生成 WAV（无外部版权素材）
├── popup.gd           可拖动 / 可关闭 / 可确认的提示弹窗（Manual / Guide 两种样式）
├── script_data.json   命令表、乱输入池、彩蛋、引导文案、三个结局
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
| `DATE` | 显示卡住的 RTC；NEW 会推荐 `SET DATE --AUTO`（NEW 的假修复，不触发 C） |
| `MANUAL` | 重新弹出已经看过的值班手册页面（不剧透未解锁内容） |
| `UNDO` | NEW 说撤销成功，OLD 说没这条命令 |
| `PUMP 3` | 看封条 |
| `PUMP 3 --ISOLATE` | 走 OLD 的机械隔离；扫描完成时 OLD 追加 `MANUAL SEAL: LOGGED` |
| `PUMP 3 --ACCEPT-NEW` | 接受 NEW 的远程修复；隐藏值 +2，右侧远程写入条亮起并同步到 2/4；扫描完成时 OLD 追加 `REMOTE WRITE: 1` |
| `SCAN` | 慢扫描（只是台词） |
| `SCAN /FULL` | 15 秒进度条 + 9 行文件系统流；2px 扫描横带随文本流在 OLD 面板上循环；约 74% 卡 99%，约 87% 回落到 97%，再走到 100%；NEW 中途插话两次 |
| `LS /VOID` / `PS` / `CAT /VOID/TECH-077` | 隐藏分区、进程、文本日志 |
| `KILL 077` | 杀掉进程；全游戏仅一次 0.5 秒屏幕乱码与 OLD `WE SAW THAT.`；8 秒后弹出假手册 07；之后 NEW 的 `/VOID` 变成 0 items；扫描完成后开启 60 秒无输入窗口（扫描前 KILL 会先记账，扫描完成时才启动） |
| `ID` | 房间里有几个人 |
| `FORMAT /VOID` | 结局 A（先逐条回放你的全部输入；restore loop 后淡出至半透明黑，显示 `SHIFT ENDED` / 重开提示，无叙事终行） |
| `SHUTDOWN --VERIFY` | 结局 B（同样先回放；播完后淡出至半透明黑，显示 `SHIFT ENDED` / 重开提示） |
| `SET DATE 2038-01-19` | 结局 C（也可输入命令 `SET DATE 2038-1-19` / `SET DATE 38-01-19`；需先完成 `SCAN /FULL`） |
| `SET DATE 2000-01-01` | 彩蛋：`NOTHING HAPPENED.` / `THAT WAS THE POINT.`（也接受 `2000-1-1` / `00-01-01`） |
| `SET DATE 1979-11-03` | 彩蛋：OLD 的上电日志（也接受 `1979-11-3` / `79-11-03`） |

输入匹配三层：精确 → 归一化/紧凑前缀补全（忽略大小写、全角字符、空格以及 `/`、`--` 的间距，例如 `PUMP` → `PUMP 3`、`SCAN/FULL` → `SCAN /FULL`）→ 多候选时取最长公共前缀；只有公共前缀本身是完整命令才自动执行，否则进入歧义态，不再替玩家挑最短命令。`FORMAT /VOID` 与 `SHUTDOWN --VERIFY` 必须完整输入，`FO` / `SH` 只会收到 `TYPE IT IN FULL.`，不能用前缀或补全直接触发不可逆结局。

输入框右侧的灰色提示只展示当前已解锁的命令：Tab 补全/循环候选，Enter 才执行；↑ / ↓ 调取真实命令历史（OLD 的 `* ` 记录不混入）。首次 `SCAN /FULL` 后才提示隐藏分区命令，读过 `CAT /VOID/TECH-077` 后才提示 `KILL 077` / A / B；KILL 且读过文件后，空输入会建议 `SHUTDOWN --VERIFY`。`SET DATE <date>` 是自由格式，不会进入 Tab 补全；HELP 列出 `DATE`，而 `DATE` 只暴露 `SET DATE` 前缀（NEW 仍推荐 `--AUTO` 假修复）。Manual 06 只说明手动写入不校验 32 位上限，不替玩家拼出完整命令。

动态威胁层：登录后第一次真实打字会弹出 `NEW · Input Access Request`，关闭后 NEW 承认 “I was already reading”；小写字母会实时转成大写（NEW 一次性认领 “OLD is helping you format them”）；第 5 次退格触发 OLD `YOU HESITATED.`（只触发一次）；OLD 的等待时间是状态读数：`/VOID` 相关 5 秒，走过 NEW 方案或乱输入 3 次 8 秒，C 窗口最后 2 秒降到 2 秒，其余 3 秒。

三个结局都要求先完成 `SCAN /FULL`。A / B 是明确的收场命令，永远优先；C 是独立的第三条路线，不会在 A / B 播放完后接管。C 有两个入口：`SET DATE 2038-*`，或 `KILL 077` 后连续 60 秒不输入任何命令。KILL 的静默窗口从扫描完成时开始计时；扫描前就 KILL 不会浪费窗口，而是在 `_finish_scan()` 里补启动。窗口会被任意一次真实输入（包括尚未提交的打字）取消，所以 `KILL 077 → LS /VOID` 仍然安全。

回放结束后、结局正文开始前，OLD 会先输出 2–3 行行动记录（coda），把这一局的选择钉在日志里：`PUMP: MANUAL SEAL.` / `PUMP: REMOTE WRITE.` / `PUMP: UNSERVICED.`，远程决策次数与是否读过 `CAT /VOID/TECH-077`，以及 `PROCESS ENDED. LOG CONTINUES.` 或乱输入条数。coda 只描述已发生的事，不改变结局判定。

A / B 为 0.9 秒淡出至半透明黑（仍能隐约看到终端），C 为 0.9 秒淡出至全黑；淡出后再等 0.25 秒显示 `SHIFT ENDED` 与 `PRESS R TO RESTART`。`SHIFT ENDED` 是 UI 状态，不属于结局叙事文本；A 仍然没有叙事终行。

三个结局在 `SHIFT ENDED` 与叙事终行之间显示身份码：`077-A · VOID EMPTY`、`077-B · STILL HERE`、`077-C · INHERIT`。它由 `Main/EndTag` 渲染（14pt、半透明绿），文本来自 `script_data.json` 的 `ending_meta`；A/B 的身份码只负责命名，不替它们补叙事终行，C 仍额外保留 `PATCH-Y2KW v2 DEPLOYED BY TECH-077`。

A 的 restore loop 在 `BOOT OK` 之后执行内部指令 `CLOCK> RESET`：时钟回到 `99-12-31 23:59:5x` 并继续爬升，EPOCH 隐藏。B 在断电舞台指示后执行 `CLOCK> DARK`：时钟停在 `--:--:--`，EPOCH 隐藏。两条 `CLOCK>` 都是 `script_data.json` 的结局内部指令，不进入 HELP。

开局输入框会预填 `LOGIN` 并全选，直接按 Enter 就会补全为 `LOGIN 077`（对应 NEW 的 “I already filled in half the login”）；也可以按 Tab 先接受右侧灰色的 `LOGIN 077`。

## 提示弹窗（值班手册）

右上角浮窗，推玩家往前走，不影响输入（弹窗开着也能继续敲命令）：

| 触发 | 内容 |
| --- | --- |
| 开局 1.2 秒 | 值班手册 01：目标、命令可自动补全、`MANUAL` / `ID`、弹窗操作说明 |
| `LOGIN 077` | 值班手册 02：`LOG` 与下一步 `PUMP 3` |
| `PUMP 3` | 值班手册 03：`--ISOLATE` / `--ACCEPT-NEW` 两条路，以及下一步 `SCAN /FULL` |
| `SCAN /FULL` 扫完 | 值班手册 04：`LS /VOID`、`PS`、`CAT /VOID/TECH-077`；随后 06：32 位上限、`2038-01-19` 提示与“手动写入不校验”（不直接给 `SET DATE` 命令） |
| `CAT /VOID/TECH-077` | 值班手册 05：`KILL 077` 与两种收场命令 |
| 首次 `KILL 077` 后 8 秒 | 假手册 07「Page Not Filed」：四条规则，按钮 `I will remember`；只弹一次，不进入 `MANUAL` 回放 |

操作：拖标题栏移动位置（自动夹在窗口内）、点右上 `×` 或按 `ESC` 关闭、点「Got it」确认。每条只弹一次，多个提示排队依次出现，进入结局时全部清空。假手册 07 走同一条弹窗队列，但不在 `MANUAL` 的白名单里；如果 8 秒内进入结局，它会被跳过。

输入 `MANUAL` 会按首次出现的顺序重新弹出**已经看过**的页面（未解锁的页面不会提前显示）；它会和普通命令一样得到 OLD / NEW 两边的回复。假手册 07 永远不会被 `MANUAL` 重放。

### 空闲引导（Guide）

与值班手册分开的第二条弹窗通道：玩家连续 20 秒没有任何键盘、鼠标点击或鼠标移动后，在画面上方居中弹出 `GUIDE · ...`。它使用金色边框区别于 Manual 的蓝色边框，`z_index` 为 200，永远盖在 Manual（100）之上；Manual 已经打开时 Guide 仍会并排出现，两者不会互相排队或顶掉。Guide 不是手册页，不写入 `_hints_seen` / `_hint_order`，`MANUAL` 不会重放它。

文案按当前进度取自 `script_data.json` 的 `guidance`：未登录 → 登录提示；未处理 pump → `PUMP 3`；未扫描 → `SCAN /FULL`；未读隐藏文件 → `LS /VOID` / `PS` / `CAT`；其余 → `HELP` / `MANUAL` / `ID`。玩家一有操作就重新计时；一次空闲只显示一个 Guide，关掉后继续空闲会再等 20 秒。进入结局时与普通弹窗一起清空。

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

`game.gd` 里：`scan_duration`（默认 15 秒）、`BOOT_TICK`（POST 行间隔 0.25 秒）、`BOOT_INTRO_HOLD`（标题停留 2 秒，整段冷启动约 3 秒）、`BOOT_INTRO_TITLE` / `BOOT_INTRO_SUB` / `BOOT_INTRO_STATUS`（冷启动过场文案）、`END_DIM_ALPHA`（A/B 半透明黑的黑度，默认 0.75）、`END_FADE_TIME`（0.9 秒）、`END_HINT_DELAY`（0.25 秒）、`GUIDE_IDLE_SEC`（空闲引导阈值，默认 20 秒；运行时可通过 `guide_idle_seconds` 覆盖，冒烟测试用于关闭或缩短）。
`Main.tscn` 里：`BootTimer.wait_time`（0.25）、`OldTimer.wait_time`（基础 3 秒，运行时由 `_old_delay_seconds()` 改写）、`ScanTimer.wait_time`（0.1）、`ReplayTimer.wait_time`（0.25）、`EndTimer.wait_time`（1.4）、`InheritTimer.wait_time`（60 秒）。动态延迟常量在 `game.gd`：`OLD_DELAY_BASE` / `OLD_DELAY_DANGER` / `OLD_DELAY_NEW_PATH` / `OLD_DELAY_ENDING_WINDOW`。
`popup.gd` 里：`WIDTH`（弹窗宽度 380）、`EDGE`（贴边留白 8）、`GUIDE_Z` / `MANUAL_Z`（引导 / 手册层级，默认 200 / 100）、`GUIDE_Y`（引导距顶 88）；Manual 出现位置在 `open()` 里计算（右上角，按 Manual 队列层叠 26px），Guide 固定在上方居中；`SFX_VOLUME_DB`（弹窗音效音量，默认 -10 dB），音源固定为根目录的 `connected.wav` / `disconnected.wav`。

## 冒烟测试

```text
godot --headless --path . --script res://tools/smoke_test.gd
```

结果写入 `smoke_result.txt`，覆盖冷启动过场（显示 / 自动交接到 POST / ESC 跳过并收起）、登录预填（Enter 信号）、命令表加载、三层匹配、提示链内容（LOG / MANUAL / ID / SCAN /FULL）、CAT 顺序保护、乱输入彩蛋、隐藏值、扫描期输入锁、扫描流与 99%→97% 回退、弹窗（出现 / 排队 / 拖拽 / 确认关闭 / 结局清空 / 音效）、选择回声（`MANUAL SEAL: LOGGED` / `REMOTE WRITE: 1`）、远程写入条（上限 4 / ACCEPT 后显示并同步）、A/B 回放、A 的 restore loop / 时钟重置 / EPOCH 隐藏 / 无 NEW 收尾 / 淡出半透明黑 / 无叙事终行 / 结束卡与身份码 / 输入框占位清除、B 的断电后时钟熄灭 / 淡出半透明黑 / 结束卡与身份码、C 的扫描门槛 / 直接日期入口 / KILL 静默入口 / 输入取消 / 扫描前 KILL 的窗口补启动 / A/B 优先 / 时钟回绕 / pre-replay 台词 / `[PATCH]` 回放 / 淡出全黑 / `PATCH-Y2KW v2` 终行 / 结束卡与身份码 / R 重置提示、两个 SET DATE 彩蛋及其短格式、三个结局的 coda、KILL 的 `WE SAW THAT.` 一次性与假手册 07（弹出 / 按钮文案 / 不进 MANUAL / 不重放）、输入归一化（大小写 / 全角 / 空格与 `/`、`--` 间距）、不可逆结局的完整输入保护、歧义前缀不自动执行、Tab 补全与候选循环、真实命令历史 ↑/↓、打字活动取消 KILL 窗口并刷新 idle 计时、补全剧情门槛与 KILL 后的 `SHUTDOWN --VERIFY` 建议、OLD 动态延迟四档、登录后授权弹窗与 `already reading` 回收、小写实时同化与 NEW 台词、第 5 次退格的 `YOU HESITATED.` 一次性、2px 扫描横带的显示/随扫描结束收起、KILL 0.5 秒乱码的显示/只播一次、Enter 后输入框保留焦点与可编辑状态、空闲引导（等待阈值 / 上下文文案 / 与 Manual 并存 / 最高层级 / 不进入 MANUAL / 鼠标活动重置 / 结局清空），以及声音层的节点/循环/状态（当前 199/199 通过）。

只检查声音节点与循环参数（不实际发声）：

```text
godot --headless --path . --script res://tools/audio_probe.gd
```

结果写入 `audio_probe.txt`，包含 4 个循环层的 `playing` / `loop_mode` / `loop_end` / 长度，以及 ACCEPT、SCAN、KILL 的状态切换。

## 导出

仓库包含 `export_presets.cfg`，提供两个预设：

| 预设 | 平台 | 输出路径 |
| --- | --- | --- |
| `Web` | Web | `../../导出包/NIGHT_SHIFT_60/Repair Permission.html` |
| `Windows Desktop` | Windows x86_64 | `../../导出包/NIGHT_SHIFT_601/Repair Permission.exe` |

Web 只能用 Compatibility 渲染器，因此 `project.godot` 已统一设为 `renderer/rendering_method="gl_compatibility"`。导出前需要在 Godot 4.7 中安装对应导出模板（编辑器 → 编辑器 → 管理导出模板）；Web 预设关闭了线程支持，普通静态服务器即可运行。

```text
godot --headless --path . --export-release "Web" "../../导出包/NIGHT_SHIFT_60/Repair Permission.html"
godot --headless --path . --export-release "Windows Desktop" "../../导出包/NIGHT_SHIFT_601/Repair Permission.exe"
```

只更新 PCK（已有模板产物时可用）：

```text
godot --headless --path . --export-pack "Windows Desktop" "Repair Permission.pck"
```

导出后至少验证：窗口 1280×720 缩放、首帧字体（`WENQUANYIDIANZHENSONGTI.TTF`）、首次输入后音频是否恢复、三个结局的 `SHIFT ENDED` / 身份码 / `PRESS R TO RESTART` 是否可见且不与终行重叠。

本次用 Godot 4.7.2 Steam 版模板重新导出 Windows：窗口 1280×720，字体与终端布局正常；`NIGHT_SHIFT_601/Repair Permission.zip` 只包含 `Repair Permission.exe` 与 `Repair Permission.pck`，不含 `_legacy/`、`tools/`、`*.md`。Web 产物按上面的 `Web` 预设单独导出，不在这个 Windows 包内。

## 已知取舍

- A / B / C 都只要求 `SCAN /FULL` 完成，不要求玩家读过手册页；如果扫描前输入 `FORMAT /VOID` / `SHUTDOWN --VERIFY`，OLD 会回 `UNKNOWN PARTITION.`。手册页只保证 04 → 05 的顺序（扫描前触发 `CAT` 会先排 04）。
- A 结局是 restore loop：`FORMAT /VOID` 回放后重启到 `PLEASE LOG IN` / `> LOGIN`，时钟被 `CLOCK> RESET` 拨回 `99-12-31 23:59:5x` 并继续爬升；再淡出到半透明黑并显示 `SHIFT ENDED` / 身份码 / `PRESS R TO RESTART`，没有叙事终行；NEW 的两句结局收尾台词已删除，但命令确认仍保留。
- B 结局在断电舞台指示后执行 `CLOCK> DARK`，时钟停在 `--:--:--`，再淡出至半透明黑，保留“机器还亮着”的隐约轮廓，同时出现 `SHIFT ENDED` / 身份码 / `PRESS R TO RESTART`。
- C 的 KILL 静默窗口是 60 秒，从 `SCAN /FULL` 完成时开始计时；扫描前的 KILL 会在 `_finish_scan()` 里补启动，不会白烧窗口。任何真实输入都会取消；它不会在 A / B 结束后被重新启动或接管。C 的 pre-replay 台词在 `script_data.json` 的 `inherit_intro`，回放后的收尾与终行在 `endings.inherit`；计时器是 `Main/InheritTimer`；全黑淡出后显示 `SHIFT ENDED` / 身份码 / `PRESS R TO RESTART`，随后是 `PATCH-Y2KW v2` 终行。
- 左上角铭牌改成了 `1999`，但剧情文本里仍保留 `YEAR 1979`、`LOG 11-03-1979`、`SEALED 1979`、`UPTIME 46Y`（`PS` 的「年份一直是错的」正是靠这些数字成立）。要全局统一成 1999，需要同时改 `boot.old`、`LOG`、`PUMP 3`、彩蛋、三个结局和 `PS` 的 `UPTIME`。
- 开机先播约 1 秒的冷启动过场（黑场、绿色扫描线、标题牌、轻微断电闪烁），随后才进入原来的逐行 POST；整段开机仍可用 ESC 立即跳过，跳过会直接打印完整 POST 日志并收起过场。过场是运行时创建的 `CanvasLayer(5)`，不占 `Main.tscn` 的终端布局，也不会挡住之后的 Manual / Guide（`CanvasLayer(10)`）。
- 弹窗不暂停游戏、不抢输入焦点，所以开着弹窗也能继续敲命令；按钮与面板都不拿键盘焦点。输入框启用 `keep_editing_on_text_submit`，按 Enter 执行后会清空旧命令并继续保留焦点与光标；点击弹窗仍可能让输入框失焦，这是预期的终端/窗口边界。
- 空闲引导独立于 Manual 队列：最多同时存在一个 Guide，Manual 可与其并存；Guide 不进入 `MANUAL` 历史、不改变结局，也不打断正在输入的文字。鼠标移动同样算活动，避免玩家只是在阅读时被弹窗盖住。
- 声音只有 A 档环境层（见「声音」），没有旋律 BGM、没有独立音量设置/静音键；素材为程序合成，适合 Jam 原型，正式版可替换为录制素材。
- 没有存档；导出预设、输出路径和 Web 渲染器限制见「导出」。`NIGHT_SHIFT_601` 用于 Windows 产物，与 Web 的 `NIGHT_SHIFT_60` 分开，避免互相覆盖。
- `PUMP 3 --ACCEPT-NEW` 的隐藏值 `temp` 每次 +2（`SET DATE --AUTO` 同样 +2），远程写入条上限 4；除结局 coda 的计数外不参与任何判定，也不会锁死路线。`--ISOLATE` 不加隐藏值。
- `WE SAW THAT.`、KILL 乱码与假手册 07 都只触发一次（重复 `KILL 077` 不会再次输出/弹出/闪烁）；假手册 07 默认在首次 KILL 后 8 秒出现，若这 8 秒内进入结局则直接跳过。它不是普通手册页，`MANUAL` 永远不重放，也不会写入 `_hints_seen` / `_hint_order`。授权弹窗同样不入 `MANUAL`，只负责把“NEW 已经在读”这件事说破。
- OLD 的动态延迟只改 `OldTimer.wait_time`，不改变输出顺序；同一次排队中的后续行不会重置已经开始的等待。冒烟测试通过 `old_delay_override` 固定为 0.05 秒，并在开局把 `Engine.time_scale` 设为 4.0，避免把 183 项断言拖成真实等待；`_finish()` 会恢复 1.0。
- 扫描横带只覆盖 `OldText` 的可视矩形，不拦截鼠标；输入同化只改字母大小写并保留光标列，不改变命令归一化、补全或历史记录。退格计数在输入框内记录，第 5 次触发一次，不写入结局 coda。
- 三个结局的 coda 只追加在回放之后、结局正文之前，纯文本、可跳过；它不会改变结局判定，也不破坏 A“无叙事终行”的收场结构。
