# sysu-xyh2026

学习 / 研究 / 工具类产出。当前主要是可复用的 **Agent skills**。

## skills

每个目录一个 skill，内含 `SKILL.md`（Agent 的入口文件）与随附脚本/模板/参考资料。
使用方式：把该目录放进你的 skills 目录即可。

| Skill | 说明 |
|---|---|
| [dsh-desktop-wallpaper](skills/dsh-desktop-wallpaper/) | 给 DeepSeek Harness 桌面应用（Electron）做**动态壁纸**：唯一验证可行的注入路径（本地安装的 DSH 客户端插件）、Wallpaper Engine / Steam 创意工坊素材的获取引导（含"复制工坊链接给 Agent"的标准操作）、以及**五个失败方案的实测档案** |

### dsh-desktop-wallpaper 速览

> 上手入口（含可直接发给 Agent 的说明）：[GETTING-STARTED.md](skills/dsh-desktop-wallpaper/GETTING-STARTED.md)


- **做什么**：把视频/图片变成 DSH 桌面窗口的背景壁纸，左下角带开关胶囊。
- **怎么做**：一个 DSH 客户端插件（`template/plugin/`），装在固定本地目录；**不需要**调试端口、守护进程、浏览器扩展。
- **一句话经验**：插件里**不要**注册 `ctx.effect(teardown)`，插件目录**不要**放可移动盘。
- **一键安装**：`powershell -ExecutionPolicy Bypass -File skills/dsh-desktop-wallpaper/scripts/install-plugin.ps1 -PluginDir skills/dsh-desktop-wallpaper/template/plugin`
- **素材**：仓库**不附带**任何第三方壁纸文件；由用户自行在 Steam 订阅，脚本负责本机定位（`discover-wallpaper.ps1`，支持直接粘贴工坊 URL）。
- 详见该目录的 [README](skills/dsh-desktop-wallpaper/README.md) 与 [failure-modes](skills/dsh-desktop-wallpaper/reference/failure-modes.md)。

## 发布清单（维护者自用）

公开仓库后建议补齐以下项，便于被搜索到、被 Agent 正确召回：

- [ ] **About → Description**：
      `Agent skills for DeepSeek Harness — starting with a live-wallpaper skill for the desktop app.`
- [ ] **About → Topics**：`deepseek-harness` `agent-skills` `electron` `wallpaper-engine` `steam-workshop`
- [ ] **License 显示**：仓库根已有 `LICENSE`（MIT）；确认仓库页右上显示 `MIT license`，否则在 `About` 里手动关联。
- [ ] **协作与权限**：公开仓库默认「人人可读、可 fork、可提 PR，但不能直推」；
      需要他人直接改动时，到 `Settings → Collaborators` 邀请。
- [ ] **不接收第三方素材**：`.gitignore` 已挡掉 `*.mp4` / `*.webm` / `_frames/` 等；
      PR 里若出现壁纸原图、视频、预览图，一律拒绝（版权 + 体积）。
- [ ] **提交前自检**（本项目实际用过的三条）：
      1. skill 目录内无媒体文件；
      2. 全仓库无个人机器路径（`C:\Users\<name>`、工作盘绝对路径）；
      3. PowerShell / JS 产物均可 `--check` 通过。
