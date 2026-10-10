# dsh-desktop-wallpaper

给 **DeepSeek Harness 桌面应用**（Electron）加**动态壁纸 / 视频背景 / 静态背景**的一个 DSH 客户端插件，
以及把它装稳所需的全部说明。

> 一句话结论：**做成本地安装的 DSH 客户端插件，插件放在固定本地盘，并且不要注册 `ctx.effect(teardown)`。**
> 之后用户**正常点图标启动**就能看到壁纸 —— 不需要调试端口、不需要守护进程、不需要浏览器扩展。

## 为什么不是别的做法

这个目标看起来简单，但有 5 条看似可行的路都被实测否掉了：

| 方案 | 结果 |
|---|---|
| 改 `app.asar` 里的前端资源 | ❌ 破坏 Vite 预打包模块 → **启动白屏**（要重装组件才恢复） |
| 浏览器用户脚本（Tampermonkey） | ❌ 桌面窗口是 `dsh-app://` 自定义协议，**不运行浏览器扩展** |
| Chrome/Edge 扩展（`--load-extension`） | ❌ 扩展能加载，但 **content script 不注入自定义协议页面** |
| 调试端口 + 外部注入器 | ⚠️ 技术上可行且稳定，但**端口必须启动时给** → 用户手动启动就没壁纸，于是必然演变成"自检重启应用"这种怪行为 |
| 插件面板"添加本地目录" | ⚠️ 部分发行版会写出依赖但**漏掉 node_modules 链接** → `failed to import` |

细节、现象与判定方法见 [reference/failure-modes.md](reference/failure-modes.md)。

## 先看这个

- 使用者上手 / 交给 Agent 的一段话：[GETTING-STARTED.md](GETTING-STARTED.md)

## 卡顿？先看这个

- 4K 视频当背景会掉帧（实测 51% → 转 1080p 后 4%）：[reference/performance.md](reference/performance.md)

## 安装

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-plugin.ps1 -PluginDir .\template\plugin
```

可选参数：

| 参数 | 默认 | 说明 |
|---|---|---|
| `-InstallDir` | `%LOCALAPPDATA%\dsh-wallpaper\plugin` | 插件运行的**固定本地目录**（绝不要放可移动盘） |
| `-ProfileName` | `desktop` | 装到哪个 DSH profile |
| `-DshHome` | `%DSH_HOME%` 或 `~\.dsh` | DSH 家目录 |

脚本会处理四处并做自检：profile 的 `dependencies`、`dsh.profile.bundles`、`node_modules` junction、`pnpm-lock.yaml` 残留路径；
最后从 profile 目录做一次裸包名解析，输出 `OK [ 'apply' ]` 才算成功。

装完**普通方式重启一次** DSH，左下角会出现：

```
wallpaper ON · live 3840x2160 (click)
```

点它可开关壁纸；关掉会恢复原本不透明的界面。

## 素材从哪来（重要）

**本仓库不附带任何壁纸素材**，`template/plugin/client.js` 里是占位 URL。素材通常来自
**Wallpaper Engine 的 Steam 创意工坊**（AppID `431960`），由**用户自己**获取：

1. 在 Steam 客户端里找到喜欢的壁纸并**订阅**（Steam 会把内容下载到本地）；
2. 用脚本定位本机文件（自动扫描所有 Steam 库）：
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\discover-wallpaper.ps1 -PublishedFileId <id> -Metadata -CopyTo D:\dsh-wallpaper\assets
   ```
3. 脚本会打印需要填进 `client.js` 的 `VIDEO_URL` / `POSTER_URL`；
4. 需要标题/标签/预览图时它还会调用 **Steam WebAPI**
   （`ISteamRemoteStorage/GetPublishedFileDetails`，**不需要**能访问 `steamcommunity.com`）。

> 我们**不**引导用户去第三方工坊下载站，也**不**把他人作品提交进仓库（含预览图）。
> 详见 [reference/getting-the-wallpaper.md](reference/getting-the-wallpaper.md)。

### 素材类型对照

| 工坊内容 | 能否直接用 | 做法 |
|---|---|---|
| `*.mp4` / `*.webm`（Video 类壁纸） | ✅ | 本地 HTTP 服务 + `VIDEO_URL` |
| 静态图（`preview.jpg` / Scene 预览） | ✅ | 直接作 `background-image` |
| `scene.pkg`（Scene 类） | ❌ | 不是普通视频；取预览图做静态背景，或让用户改选视频类壁纸 |
## 壁纸内容怎么换

- **视频**：用 `optional/video-server/` 起本地服务（仅监听 `127.0.0.1:8787`，支持 Range + CORS），
  再把 `template/plugin/client.js` 里的 `VIDEO_URL` / `POSTER_URL` 指过去。
  服务没起时只显示静态封面（**降级必须保留**，别让它白屏或报错）。
- **静态图**：直接把 data URL / 本地 URL 用作 `background-image`，不需要服务。
- **透明度**：改 `client.js` 里的 `ON_CSS`（`_frame` / `_sidebarCol` / `_centerCol` 三个 alpha）。

## 三个最容易踩的坑（务必读）

1. **别注册 `ctx.effect(teardown)`**：应用启动流程会释放这个客户端条目，teardown 会把刚画好的图层撤掉（日志显示"插入成功"但图层消失，且 MutationObserver 抓不到删除记录）。
2. **插件必须在固定本地盘**：profile 依赖是 `link:` 路径，放可移动盘会出现"拔盘就没壁纸"。
3. **半透明覆盖要命中的是硬编码颜色**：面板用的是 `rgb(27,27,28)` / `rgb(21,21,23)`，**不是** `--dsw-alias-*` 变量；用 `[class*="_frame"]` 这类属性选择器（构建哈希会变）。

## 目录结构

```
SKILL.md                      skill 说明（Agent 可直接加载）
template/plugin/              可直接安装的插件（package.json / cordis.patch.yml / index.js / client.js）
scripts/install-plugin.ps1    一键安装 + 自检
optional/video-server/        本地视频服务 + 静默启动包装
reference/failure-modes.md    五个失败方案的实测档案与判定方法
```

## 卸载

1. 从 `profiles/<name>/package.json` 删掉该依赖与 bundles 条目；
2. 删掉 `cordis.patch.yml` 里对应的 `- insert: - id: <id>`（若有）；
3. 删掉 `node_modules/@local/<pkg>`；
4. 删掉本地运行目录与相关计划任务。

**应用本身从未被修改**（`app.asar` 始终保持原样），所以不需要修复安装。

## License

MIT

## 现场记录与提交策略（重要）

本仓库鼓励 Agent 在使用 skill 时**把新知识回填**，但发布动作由人把控：

| 动作 | 谁做 | 说明 |
|---|---|---|
| 写 `reference/field-notes/*.md` | **Agent 自动** | 附带脱敏扫描（个人路径 / 令牌 / 内网 IP / SID 命中即拒绝） |
| `git commit`（本地） | **Agent 自动、静默** | 不打扰用户、不弹确认；提交尾带 `[agent-field-note]` 便于筛选 |
| `git push`（公开） | **仅仓库所有者** | Agent **永不推送**：公开历史不可撤销 |

协议全文：[skills/dsh-desktop-wallpaper/reference/field-notes/README.md](skills/dsh-desktop-wallpaper/reference/field-notes/README.md)。
筛选 Agent 提交：`git log --grep '\[agent-field-note\]'`；撤销一条：`git reset --soft HEAD~1`。