---
title: Video server kept dying, and a dead source was reported as "autoplay blocked"
date: 2026-10-10
skill: dsh-desktop-wallpaper
verified: true
environment: windows-11
dsh: 0.2.0-rc.2
tags: [video-server, autoplay, diagnosis, process-ownership]
---

## 症状（Symptom）

1. 胶囊显示 `wallpaper ON · autoplay blocked`，但界面与插件都正常。
2. 本地视频服务（127.0.0.1:8787）反复消失：日志显示它启动成功、无报错，过一会儿进程就没了。

## 复现（Repro）

1. 由**当前会话的 shell** 启动视频服务：`Start-Process node wallpaper-server.mjs`
2. 结束该 shell 会话 / 宿主重启后，服务进程随之消失
3. 页面里 `video.play()` 被拒绝，插件的 catch 把它报成 autoplay 问题

## 根因（Cause）

两件事各自成立：

- **进程归属**：由交互式 shell 启动的子进程会随该 shell/宿主一起终止。服务"消失"不是崩溃，是被连带结束。
- **错误分类**：`HTMLMediaElement.play()` 在**媒体源加载失败**时同样 reject（NotSupportedError 之类），
  插件把任何 reject 都当成"自动播放被策略拦截"，于是给出误导性的标签与建议。

实测反证（本机 Edge，视频来自同一服务）：

| 环境 | 结果 |
|---|---|
| 不加开关 | `play: RESOLVED, paused:false` |
| 加 `--autoplay-policy=no-user-gesture-required` | `play: RESOLVED, paused:false` |

静音视频本就能自动播放，所以"autoplay blocked"从一开始就是伪诊断。

## 解法（Fix）

- 让**独立于交互式会话的机制**拥有服务进程：Windows 计划任务（`Register-ScheduledTask` + `Start-ScheduledTask`）
  或同等机制；不要用"当前 shell 的子进程"承载长驻服务。
- 插件区分两类失败并分别呈现：
  `video.error || video.networkState === 3` → `source`（提示"视频源不可用 / 服务是否在跑"），
  否则才是 `blocked`（提示"点击任意处"）。控制台同时打印 `media error code`。

## 验证（Verification）

- 服务改由计划任务启动后，跨会话持续存活：`Test-NetConnection 127.0.0.1 -Port 8787` 持续为 True，
  且可正常返回 `206` 与 `Content-Range`。
- 空源与正常源两种情形下，胶囊文案分别落到 `video source down` 与 `1920x1080`（不再误报）。

## 影响与适用边界（Scope）

- 适用于任何"长驻本地辅助进程 + 宿主内嵌页面"的组合，不限于壁纸。
- 若宿主每次启动都会拉起该服务（例如宿主自带监督），则无需外部计划任务。
- 该结论不影响 4K→1080p 转码的正确性；两者是独立的性能与可用性问题。