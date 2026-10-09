---
name: dsh-desktop-wallpaper
description: Use when someone wants an animated/live wallpaper, background video, or background image behind the DeepSeek Harness DESKTOP app (Electron) - "把这个视频/壁纸设为 DSH 背景" - typically with a Wallpaper Engine workshop wallpaper on Steam as the source, or when a previously working wallpaper stopped appearing (vanishes after a restart, or after unplugging a removable drive). Covers how to guide the user to obtain the wallpaper themselves (subscribe in Steam/Wallpaper Engine, locate it locally, Steam WebAPI for metadata) and the only verified injection path (a locally installed DSH client plugin), plus why asar edits / userscripts / Chrome extensions / debug-port agents all fail here and the three traps that make the wallpaper disappear.
---

# 给 DSH 桌面应用做动态壁纸（唯一验证可行的路径）

## 结论先给

**做成本地安装的 DSH 客户端插件（client plugin），放在本地磁盘，并且不要注册 `ctx.effect(teardown)`。**

这样：**用户正常点图标启动 → 壁纸自动出现**。不需要调试端口、不需要守护进程重启应用、不需要浏览器扩展、不需要 U 盘。

## 环境事实（决定了为什么其它做法都不行）

先验证这些事实，再动手：

| 事实 | 如何验证 | 后果 |
|---|---|---|
| 桌面窗口是 Electron 自定义协议 `dsh-app://app/`，**不是** `http://127.0.0.1:19387` | 用调试端口连进渲染器读 `location.href` | Chrome/Edge 扩展的 content script **不会注入**（`chrome.runtime` 在页面里都不可见） |
| Electron 窗口**没有**用户脚本入口 | 浏览器用户脚本(Tampermonkey)只在真实浏览器里生效 | userscript 方案对桌面窗口完全无效 |
| 前端是**预打包**产物；客户端插件由主机按 `plugins/??<包名>/client.js&rev=<hash>` 提供 | 抓 `window.__DSH_BOOT__` 看 entries | 插件是**唯一**的官方注入点；`app.asar` 里没有可插入的目录索引 |
| 客户端条目在启动后会被**释放**（web boot 收集激活项时） | 插件日志显示“插入成功”，几秒后图层消失，且 MutationObserver 抓不到删除记录 | 若插件注册了 teardown，**图层会被插件自己撤掉** |
| 应用有单实例锁；`--remote-debugging-port` 必须**启动时**给 | 第二个实例不会开端口 | 事后无法注入；任何“重启应用”的自动化都会打断调用者自己的会话 |

## 三个致命陷阱（踩过，务必避免）

1. **`ctx.effect(teardown)` / 任何清理注册**
   症状：控制台能看到 `layer inserted`、`installed`，但图层随后消失，且 `MutationObserver` 记录为空。
   原因：应用启动流程释放该客户端条目 → 触发插件清理 → 图层被移除。
   对策：**让图层独立于插件生命周期**（用胶囊开关或刷新页面来移除）。

2. **插件装在可移动盘 / 非固定路径**
   症状：盘在就正常，拔盘重启后壁纸消失（`failed to import`）。
   原因：profile 的依赖是 `link:<插件路径>`，Node 解析不到模块。
   对策：**插件目录必须在固定本地盘**；profile 依赖、node_modules junction、pnpm-lock 三处都要指向本地。

3. **靠调试端口 + 外部注入器**
   症状：“必须用专用启动器启动才有壁纸”，或“自检脚本重启应用后才有壁纸”；期间还会把操作者自己的会话杀掉。
   原因：端口只能在启动时打开，注入器只能在带端口时工作。
   对策：**不要用**。若确需排查，把“杀应用 + 重启 + 探测”放进**独立于调用者进程树的计划任务**里，不要直接 `taskkill` 自己的宿主。

## 也不要做的（都实测失败）

- **改 `app.asar`**：替换 Vite 预打包模块的字节会破坏模块结构，导致**启动即白屏**（需重装组件才恢复）。
- **Chrome/Edge 扩展（`--load-extension`）**：能加载，但 content script 不注入 `dsh-app://` 页面。
- **浏览器用户脚本**：桌面窗口不运行浏览器扩展。
- **只用“添加插件”对话框输入本地目录**：在部分发行版上会写出 profile 依赖却**没有把包链接进 node_modules**，导致 `failed to import`；这种状态必须手工补链接（见下）。

## 素材从哪来（先做这一步）

**本 skill 不附带任何壁纸素材**：`client.js` 里的 `VIDEO_URL` / `POSTER_URL` 是占位地址。
素材通常来自 **Wallpaper Engine 创意工坊**（Steam AppID `431960`），流程是**引导用户自己完成**：

1. **先拿到壁纸链接（最准的一步）**：让用户在 Steam 的壁纸页面点右上角 **分享（share）** 按钮
   —— 它就挨着 **“留言 / 评论”** 入口（网页标记 `id="ShareItemBtn"`）；弹窗里的 **页面链接 / 复制链接**
   就是该壁纸 URL（一般点了就直接复制）。请用户把整条链接粘给你，你再取 `?id=<数字>`。
   > 如果用户已经在浏览器里打开该页面，直接复制地址栏里的 `.../sharedfiles/filedetails/?id=<id>` 也一样。
2. 询问用户：类型（**视频** / **静态图** / **scene 工程**），以及是否已经**订阅**。
3. 让用户在 **Steam 客户端**里找到该壁纸并点 **订阅**（Steam 会下载到本地缓存）。
   - **不要**引导用户去第三方工坊下载站；**不要**替用户下载或散布他人作品。
4. 用脚本定位本机文件并（可选）复制到固定本地目录：
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\discover-wallpaper.ps1 -PublishedFileId <id> -Metadata -CopyTo D:\dsh-wallpaper\assets
   ```
   它会解析 `libraryfolders.vdf` 找出所有 Steam 库，定位
   `<lib>\steamapps\workshop\content\431960\<id>\`，列出内容并判定类型。
5. 需要标题/标签/预览图时用 **Steam WebAPI**（若 `steamcommunity.com` 打不开也可用）：
   `POST https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/`，
   取 `title` / `tags` / `preview_url`（大图可加 `?imw=3840&imh=2160&ima=fit&impolicy=Letterbox`）。
   > 未登录状态下工坊页面里**没有直链**，别去抓网页找下载地址。
6. `scene.pkg`（scene 类壁纸）不是普通视频，只能取预览图做静态背景，或让用户换视频类壁纸。

详细检查清单与版权注意：`reference/getting-the-wallpaper.md`。

**合规红线**：不要把第三方壁纸文件（含预览图）提交进要开源的仓库，只保留代码与占位 URL。
## 快速部署

### 方式 A：一键脚本（推荐）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-plugin.ps1 -PluginDir .\template\plugin
```

脚本会：复制插件到固定本地目录 → 写 profile 的依赖与 bundles → 重建 junction → 修正 pnpm-lock 里的旧路径 → **从 profile 目录做一次裸包名解析自检**。

### 方式 B：手工 4 步

设 `RT` 为固定本地目录（例 `%LOCALAPPDATA%\dsh-wallpaper`），`PROFILE` 为 `$env:DSH_HOME\profiles\desktop`。

1. 把 `template/plugin/` 整个复制到 `RT\plugin`。
2. 编辑 `PROFILE\package.json`：
   ```json
   {
     "name": "dsh-profile-desktop",
     "private": true,
     "dependencies": { "@local/dsh-wallpaper-live": "link:D:/dsh-wallpaper/plugin" },
     "dsh": { "profile": { "bundles": [
       "@deepseek-ai/dsh-base",
       "@deepseek-ai/dsh-web-app",
       "@local/dsh-wallpaper-live"
     ] } }
   }
   ```
   > `dependencies` 与 `bundles` **两处都要有**：前者决定能否 import，后者决定是否进入插件树。
3. 重建链接（旧的可能指向别处或是断的）：
   ```powershell
   $link = "$PROFILE\node_modules\@local\dsh-wallpaper-live"
   if (Test-Path $link) { (Get-Item $link).Delete() }
   New-Item -ItemType Junction -Path $link -Target "$RT\plugin" | Out-Null
   ```
4. `PROFILE\pnpm-lock.yaml` 里若残留旧路径（如 `link:E:/.../plugin`）也替换成本地路径。

**验收**（不改动应用、不重启）：

```powershell
cd $PROFILE
node -e "import('@local/dsh-wallpaper-live').then(m=>console.log('OK',Object.keys(m))).catch(e=>console.log('FAIL',e.code,e.message))"
# 期望：OK [ 'apply' ]
```

再用 Electron 本体复验（那才是应用真正的加载器）：

```powershell
$env:ELECTRON_RUN_AS_NODE='1'
& "<DSH 安装目录>\DeepSeek Harness.exe" -e "import('@local/dsh-wallpaper-live').then(m=>console.log('OK',Object.keys(m))).catch(e=>console.log('FAIL',e.code,e.message))"
```

> **工作目录必须是 profile 目录**，否则会得到误导性的 `ERR_MODULE_NOT_FOUND`。

最后让用户**普通方式重启一次**应用：左下角应出现胶囊 `wallpaper ON · live <W>x<H> (click)`。

## 插件设计要点（模板已按此实现）

- 宿主半边 `index.js` 只需 `export function apply() {}`（浏览器半边负责渲染）。
- 浏览器半边用 `window.__ModuleLoader__.load({ id: '<包名>', factory(require) { return { inject: [], apply(ctx) { ... } } } })` 注册；`id` 必须与 `package.json` 的 `"name"` 完全一致。
- 渲染层插到 `<body>` 的**第一个子节点**，`position:fixed; inset:0; z-index:-1; pointer-events:none`：必定在 `#root` 之下，不参与布局、不吃点击。
- **`inject: []` 是合法的**；`dsh.client` 写 `{"platform":"web","immediately":true,"inject":[]}`。
- **不要注册 `ctx.effect(teardown)`**；需要关闭入口时用胶囊按钮或刷新页面。
- 图层丢失时自愈：打开页面后起一个 2 秒 `setInterval` 巡检补回，成本极低。
- 遮罩/暗角用 `::after` 或子元素渐变，保证文字可读。

### “界面不透、壁纸被挡”这一坑

**不要只改 `--dsw-alias-*` 变量**——实测主框架/侧栏/中栏用的是**硬编码颜色**（`rgb(27,27,28)` / `rgb(21,21,23)`）。必须用属性选择器命中类名（构建哈希会变，所以用 `[class*="_frame"]` 这种写法）：

```css
[class*="_frame"]{background-color:rgba(27,27,28,.42) !important}
[class*="_sidebarCol"]{background-color:rgba(27,27,28,.40) !important}
[class*="_centerCol"]{background-color:rgba(21,21,23,.34) !important}
[class*="_root"]{background-color:transparent !important}
[class*="_emptyTabHost"]{background-color:transparent !important}
html,body{background:transparent !important}
```

这三个 alpha 越小越透（文字对比度越低）。改完刷新页面即生效。

## 视频/图片怎么接进插件（素材来源见上一节）

- 插件客户端只能拿 URL。若壁纸是视频，**放在本地 HTTP 服务上**（见 `optional/video-server/`，仅监听 `127.0.0.1:8787`，支持 Range 与 CORS）。
- **必须保留降级**：服务没起时只显示静态封面并在控制台提示，不白屏、不破坏界面。
- 若壁纸是静态图：直接用 data URL 或本地 URL 作 `background-image`，无需服务。

## 可选：视频服务随登录静默启动

```powershell
$act = New-ScheduledTaskAction -Execute "wscript.exe" -Argument ('"' + $RT + '\start-video-server-silent.vbs"')
$trg = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"; $trg.Delay = 'PT15S'
$set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
$prn = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName 'DSH Wallpaper Video Server' -Action $act -Trigger $trg -Settings $set -Principal $prn -Force
```

用 `wscript.exe` + `.vbs` 包装是为了**不弹黑窗**（用 `cmd /c start ...` 会弹）。

## 遇到未覆盖的问题并解决后：回填现场记录

**策略：Agent 自动落盘 + 本地提交（静默，不打扰用户）；推送永远由仓库所有者人工完成。**

完整协议见 `reference/field-notes/README.md`。要点：

- **什么时候写**（三条同时成立）：skill 文档/脚本里确实没有 → 你已实际解决并验证 → 对他人可复用。
  纯环境问题（盘掉了、代理没开、权限不足）**不要**写进仓库。
- **写到哪**：`reference/field-notes/YYYY-MM-DD-<slug>.md`，用协议里的模板
  （症状 / 复现 / 根因 / 解法 / 验证 / 适用边界）。
- **顺手回填**：若 `SKILL.md` 里有对应的过时或缺失表述，一并修正 —— 这才是知识回填的重点。
- **怎么做**（推荐用脚本，它内置换行前面的脱敏扫描与本地提交）：
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\record-field-note.ps1 `
    -Title "<一句话>" -Symptom "<现象>" -Cause "<根因>" -Fix "<解法>" -Verification "<怎么验证>"
  ```
  脚本**不含任何 push 逻辑**；连远端都不需要存在。
- **绝不推送**：本仓库是 Public，推送即进入不可逆的公开历史。
  提交之后，只需（如用户问起）说明"已在本地提交 N 条现场记录，需要你在 GitHub Desktop 点一次 Push 才会公开"。
- **不要打扰用户**：本地提交是静默动作，不弹确认、不要求用户操作。
- **尊重只读场景**：若用户声明"skills 目录只读"、或该副本从只读位置加载，
  **只把记录内容输出到对话**，不做任何 git 操作。
- **脱敏红线**：field notes 会被全世界看到。禁止写入个人绝对路径、主机名、令牌、
  内网 IP、SID/GUID；描述环境用类型化说法（`windows-11`、`default profile`、`non-ASCII install path`）。
  脚本会强制扫描并在命中时**拒绝写入**（退码 2）。
## 卸载

1. 删除 `PROFILE\package.json` 里的 `@local/dsh-wallpaper-live`（依赖与 bundles 两处）。
2. 删除 `PROFILE\cordis.patch.yml` 里对应的 `- insert: - id: dsh-wallpaper-live` 行（若有）。
3. 删除 `PROFILE\node_modules\@local\dsh-wallpaper-live`。
4. 删除本地运行目录与（若有）计划任务。

应用本身从未被修改，无需修复。

## 文件

| 路径 | 用途 |
|---|---|
| `template/plugin/` | **可直接安装的插件**（package.json / cordis.patch.yml / index.js / client.js） |
| `scripts/install-plugin.ps1` | 一键安装 + 自检 |
| `scripts/discover-wallpaper.ps1` | 定位本机（Steam 创意工坊）壁纸文件 + 取 WebAPI 元数据 |
| `reference/getting-the-wallpaper.md` | 素材获取引导与合规注意（Agent 检查清单） |
| `optional/video-server/wallpaper-server.mjs` | 本地视频服务（Range + CORS，仅 127.0.0.1） |
| `optional/video-server/start-video-server-silent.vbs` | 静默启动包装（计划任务用） |
| `reference/failure-modes.md` | 各失败方案的实测现象与判定方法 |
| `reference/field-notes/` | **现场记录**：skill 未覆盖的问题与解法（含回填协议） |
| `scripts/record-field-note.ps1` | 写现场记录 + **仅本地**提交（脱敏扫描，绝不推送） |