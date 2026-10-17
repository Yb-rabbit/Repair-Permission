# Repair Permission

3 小时 Jam 版终端微恐怖。玩家是夜班技师 TECH-077，面前两台机器：OLD（1979 年绿字终端，延迟 3 秒，全大写，记录一切）和 NEW（现代助手，秒回，会替你做决定）。没有 jump scare，恐怖只来自信息错位。

## 运行

Godot 4.7 打开项目，`F5`。主场景 `res://Main.tscn`，脚本 `res://game.gd`，数据 `res://script_data.json`。

## 结构

```text
res://
├── Main.tscn          Control 场景（双 RichTextLabel / 3 ProgressBar / LineEdit / CRT 空槽 / Popups 图层 / 4 Timer）
├── game.gd            全部逻辑，约 400 行
├── popup.gd           可拖动 / 可关闭 / 可确认的提示弹窗
├── script_data.json   命令表、乱输入池、彩蛋、两个结局
├── tools/smoke_test.gd
└── _legacy/           v1 实现与旧脚本（归档，不参与运行）
```

CRT 覆盖层是 `Main/CRT`（颜色 alpha 0、鼠标忽略），拿到 `crt.gdshader` 后新建 ShaderMaterial 挂上去即可。弹窗挂在 `Main/Popups`（CanvasLayer layer 10）上，永远画在 CRT 与终端之上。

## 语言与字体

运行时全部界面文案（终端输出、输入提示、值班手册弹窗、按钮与工具提示）均为英文，对白文本集中在 `script_data.json`，界面固定文案在 `game.gd` / `popup.gd`。

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
| `SCAN /FULL` | 15 秒进度条，NEW 中途插话两次 |
| `LS /VOID` / `PS` / `CAT /VOID/TECH-077` | 隐藏分区、进程、文本日志 |
| `KILL 077` | 杀掉进程；之后 NEW 的 `/VOID` 变成 0 items |
| `ID` | 房间里有几个人 |
| `FORMAT /VOID` | 结局 A（先逐条回放你的全部输入） |
| `SHUTDOWN --VERIFY` | 结局 B（同样先回放） |

输入匹配三层：精确 → `begins_with` 补全（例如 `PUMP` → `PUMP 3`，NEW 代跑、OLD 纠错）→ 完全不匹配走气氛回复；乱输入第 3 次触发 OLD 彩蛋。

开局输入框会预填 `LOGIN` 并全选，直接按 Enter 就会补全为 `LOGIN 077`（对应 NEW 的 “I already filled in half the login”）。

## 提示弹窗（值班手册）

右上角浮窗，推玩家往前走，不影响输入（弹窗开着也能继续敲命令）：

| 触发 | 内容 |
| --- | --- |
| 开局 1.2 秒 | 值班手册 01：目标、命令可自动补全、`MANUAL` / `ID`、弹窗操作说明 |
| `LOGIN 077` | 值班手册 02：`LOG` 与下一步 `PUMP 3` |
| `PUMP 3` | 值班手册 03：`--ISOLATE` / `--ACCEPT-NEW` 两条路，以及下一步 `SCAN /FULL` |
| `SCAN /FULL` 扫完 | 值班手册 04：`LS /VOID`、`PS`、`CAT /VOID/TECH-077` |
| `CAT /VOID/TECH-077` | 值班手册 05：`KILL 077` 与两种收场命令 |

操作：拖标题栏移动位置（自动夹在窗口内）、点右上 `×` 或按 `ESC` 关闭、点「Got it」确认。每条只弹一次，多个提示排队依次出现，进入结局时全部清空。

输入 `MANUAL` 会按首次出现的顺序重新弹出**已经看过**的页面（未解锁的页面不会提前显示）；它会和普通命令一样得到 OLD / NEW 两边的回复。

顺序保护：如果玩家在扫描前就输入 `CAT /VOID/TECH-077`，会先把手册 04 排进队列，再排 05，避免跳过隐藏分区说明。

新增提示：在 `game.gd:_hint_for()` 里加一个 `match` 分支调用 `_hint("唯一id", "标题", "BBCode 正文")` 即可。

## 调参

`game.gd` 里：`scan_duration`（默认 15 秒）。
`Main.tscn` 里：`OldTimer.wait_time`（默认 3 秒）、`ScanTimer.wait_time`（0.1）、`ReplayTimer.wait_time`（0.25）、`EndTimer.wait_time`（1.4）。
`popup.gd` 里：`WIDTH`（弹窗宽度 380）、`EDGE`（贴边留白 8）；出现位置在 `open()` 里计算（右上角，按队列层叠 26px）。

## 冒烟测试

```text
godot --headless --path . --script res://tools/smoke_test.gd
```

结果写入 `smoke_result.txt`，覆盖登录预填（Enter 信号）、命令表加载、三层匹配、提示链内容（LOG / MANUAL / ID / SCAN /FULL）、CAT 顺序保护、乱输入彩蛋、隐藏值、扫描期输入锁、弹窗（出现 / 排队 / 拖拽 / 确认关闭 / 结局清空）、回放与结局完成度（当前 40/40 通过）。

## 已知取舍

- 命令本身不做章节门禁：开局直接输入 `FORMAT /VOID` / `SHUTDOWN --VERIFY` 仍可跳关；手册页只保证 04 → 05 的顺序（扫描前触发 `CAT` 会先排 04）。
- 结局 C（60 秒静默）按决定砍掉，`data` 里也没有它的文本；要恢复只需加一段 `endings.timeout` 和一个静默计时。
- 左上角铭牌改成了 `1999`，但剧情文本里仍保留 `YEAR 1979`、`LOG 11-03-1979`、`SEALED 1979`、`UPTIME 46Y`（`PS` 的「年份一直是错的」正是靠这些数字成立）。要全局统一成 1999，需要同时改 `boot.old`、`LOG`、`PUMP 3`、彩蛋、两个结局和 `PS` 的 `UPTIME`。
- 弹窗不暂停游戏、不抢输入焦点，所以开着弹窗也能继续敲命令；按钮与面板都不拿键盘焦点。
- 没有音效、没有存档、没有导出配置。
