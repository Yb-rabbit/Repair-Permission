# Repair Permission

3 小时 Jam 版终端微恐怖。玩家是夜班技师 TECH-077，面前两台机器：OLD（1979 年绿字终端，延迟 3 秒，全大写，记录一切）和 NEW（现代助手，秒回，会替你做决定）。没有 jump scare，恐怖只来自信息错位。

## 运行

Godot 4.7 打开项目，`F5`。主场景 `res://Main.tscn`，脚本 `res://game.gd`，数据 `res://script_data.json`。

## 结构

```text
res://
├── Main.tscn          Control 场景（双 RichTextLabel / 3 ProgressBar / LineEdit / CRT 空槽 / 4 Timer）
├── game.gd            全部逻辑，约 330 行
├── script_data.json   命令表、乱输入池、彩蛋、两个结局
├── tools/smoke_test.gd
└── _legacy/           v1 实现与旧脚本（归档，不参与运行）
```

CRT 覆盖层是 `Main/CRT`（颜色 alpha 0、鼠标忽略），拿到 `crt.gdshader` 后新建 ShaderMaterial 挂上去即可。

## 命令

| 命令 | 作用 |
| --- | --- |
| `LOGIN 077` | 登录。OLD 回 `ONE TERMINAL` |
| `HELP` / `STATUS` / `LOG` | 教学 / 状态 / 1979 年日志 |
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

## 调参

`game.gd` 里：`scan_duration`（默认 15 秒）。
`Main.tscn` 里：`OldTimer.wait_time`（默认 3 秒）、`ScanTimer.wait_time`（0.1）、`ReplayTimer.wait_time`（0.25）、`EndTimer.wait_time`（1.4）。

## 冒烟测试

```text
godot --headless --path . --script res://tools/smoke_test.gd
```

结果写入 `smoke_result.txt`，覆盖命令表加载、三层匹配、乱输入彩蛋、隐藏值、扫描期输入锁、回放与结局完成度（当前 22/22 通过）。

## 已知取舍

- 结局 C（60 秒静默）按决定砍掉，`data` 里也没有它的文本；要恢复只需加一段 `endings.timeout` 和一个静默计时。
- 没有音效、没有存档、没有导出配置。
