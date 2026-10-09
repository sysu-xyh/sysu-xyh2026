# 现场记录协议（field notes）

本文件规定：**当调用本 skill 的 Agent 遇到 skill 未覆盖的问题、并最终解决之后，如何把新知识补回仓库。**

## 铁律

| 允许 | 禁止 |
|---|---|
| 在 `reference/field-notes/` 新增一条**脱敏**记录 | ❌ **绝不 `git push`**（推送必须由仓库所有者人工完成） |
| 更新 `SKILL.md` / `README.md` 里对应的一行或小节 | ❌ 不写入任何个人路径、用户名、主机名、令牌、内网地址、SID、GUID |
| **本地** `git commit`（静默执行，不打扰用户） | ❌ 不把第三方素材（壁纸原图/视频/预览图）加进仓库 |
| 记录"复现步骤 + 根因 + 验证方式" | ❌ 不提交未验证的猜测；不确定就标 `verified: false` |

> 为什么不能自动推送：本仓库是 **Public**。一旦推送，内容进入不可逆的公开历史（爬虫/镜像几分钟内就会抓到）。
> 本地提交让 Agent 的产出**不会丢失**且完全可编辑，而"发布到公网"这一步由人把控。

## 什么时候写

**仅当三条同时成立**：

1. 遇到的问题**在本 skill 的文档/脚本中没有任何说明**（不是"我没看"，是真的缺）；
2. 该问题已被**实际解决**，并且你**验证过**解决有效（有可复现的验证证据）；
3. 它对其他人**可复用**（是通例，不是这台机器的偶发故障）。

若只是本机环境问题（磁盘掉了、代理没开、权限不足），**不要**写进仓库 —— 那属于环境，不是知识。

## 写到哪

```
reference/field-notes/YYYY-MM-DD-<kebab-slug>.md
```

文件名用 UTC 日期 + 短横线 slug，例如 `2026-10-09-scene-pkg-not-a-video.md`。

推荐用脚本生成（它做脱敏 + 密钥扫描 + 本地提交，**不会推送**）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\record-field-note.ps1 `
  -Title "Scene-type wallpapers have no video file" `
  -Symptom "workshop 目录里只有 scene.pkg，没有 mp4" `
  -Cause "scene 工程是 Wallpaper Engine 自有格式，不是视频容器" `
  -Fix "改用该条目的 preview 图作静态背景，或让用户换 Video 类壁纸" `
  -Verified "在本机 431960 的 scene 条目上确认无 mp4 可提取"
```

## 记录模板

```markdown
---
title: <一句话标题>
date: <YYYY-MM-DD>
skill: dsh-desktop-wallpaper
verified: true|false
environment: windows-11 | windows-10 | other
dsh: <DSH 版本；未知写 unknown>
tags: [plugin, install, video, workshop, ...]
---

## 症状（Symptom）

<用户/Agent 能看到的现象。只写现象，不写猜测。>

## 复现（Repro）

1. <最小步骤>

## 根因（Cause）

<为什么。给出证据来源：日志行、实测命令与输出摘要 —— 需脱敏。>

## 解法（Fix）

<具体做法；涉及文件/参数时给出确切键名或代码片段。>

## 验证（Verification）

<怎么证明有效：命令 + 期望输出要点。>

## 影响与适用边界（Scope）

<何时适用、何时不适用；是否与既有文档冲突并已修正。>
```

## 提交规范（仅本地）

```
field-notes: <短标题>

<2-4 行：症状 / 根因 / 解法 / 验证方式>

[agent-field-note] verified=<true|false> machine=<windows-11|...> dsh=<version> skill=dsh-desktop-wallpaper
```

尾部标签便于仓库所有者筛选与回滚：`git log --grep '\[agent-field-note\]'`。

## 提交前的强制自检（脚本已内置）

1. **敏感信息扫描**：拒绝写入或提交包含以下模式的内容
   - 个人目录：`C:\Users\<name>`、`/home/<name>`、展开后的 `~` 绝对路径
   - 凭据：`ghp_`、`github_pat_`、`sk-`、`Bearer `、`token=`、`password=`、`-----BEGIN`
   - 网络：内网 IP（`10.`、`192.168.`、`172.16-31.`）、`.local`、公司域名
   - 机器标识：主机名、SID（`S-1-5-...`）、GUID 形式的机器码
2. **媒体扫描**：拒绝提交 `*.mp4`、`*.webm`、`*.jpg`、`*.png`、`*.webp`、`*.gif`
3. **范围扫描**：只允许改动 `reference/field-notes/**`、`SKILL.md`、`README.md`、`reference/*.md`
4. **推送防护**：脚本**不含任何 push 逻辑**；建议对 `main` 开启分支保护并要求 PR

## 给 Agent 的执行顺序

1. 解决问题并验证。
2. 判断是否符合"什么时候写"三条。
3. 写 field note（用模板；宁缺毋滥）。
4. 若 `SKILL.md` 里有相应的过时/缺失表述，**一并修正**（这是知识回填的重点）。
5. 运行 `record-field-note.ps1`（或手工执行等价的 `git add` + `git commit`）。
6. **不推送**。若用户问起，说明"已在本地提交 N 条现场记录，需要你在 GitHub Desktop 点一次 Push 才会公开"。
7. 若用户明确表示不希望仓库被改动（例如 skill 从只读位置加载、或用户声明"只读"），则**只把记录内容输出到对话**，不做任何 git 操作。

## 隐私与边界

- field notes 是**公开文档**，请按"会被全世界看到"的标准书写。
- 不要写用户的个人环境细节；需要描述环境时用**类型化**说法（`windows-11`、`default profile`、`non-ASCII install path`）。
- 记录里可以引用**本项目已有的**路径约定（如 `%DSH_HOME%\profiles\desktop`），但不要引用用户独有的绝对路径。