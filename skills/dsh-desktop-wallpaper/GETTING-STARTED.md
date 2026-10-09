# Getting started（给使用者 / 给 Agent）

给 **DeepSeek Harness 桌面应用**加**动态壁纸**。安装是一次性的，之后**正常启动就有壁纸**。

---

## 一、最快路径：把下面这段直接发给你的 Agent

> 帮我装这个动态壁纸 skill：
> ```
> git clone https://github.com/sysu-xyh/sysu-xyh2026.git "$env:TEMP\sysu-repo"
> powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\sysu-repo\skills\dsh-desktop-wallpaper\scripts\bootstrap.ps1"
> ```
> 装完把结果告我，并带我完成剩下两步（订阅壁纸、重启 Harness）。

Agent 会做：① 把 skill 链接进 `$DSH_HOME\skills\`（技能目录立即刷新，无需重启）② 把壁纸插件装进 Harness 的 profile 并**自检导入** ③ 启动本地视频服务 + 注册登录自启任务。

---

## 二、Agent 能自动做 / 你必须自己做

| 步骤 | 谁做 | 说明 |
|---|---|---|
| 取回并安装 skill 与插件 | **Agent** | 已验证：写依赖 + bundles + junction + 自检 `import` |
| 起视频服务、注册登录自启 | **Agent** | 静默任务，登录后自动跑 |
| 定位你本机的壁纸文件 | **Agent** | 你只需把工坊链接给它 |
| **在 Steam 里"订阅"壁纸** | **你** | 版权 + 登录态，Agent 不能代做；订阅后 Steam 才会把文件下到本地 |
| **重启一次 Harness** | **你** | 客户端插件要随启动加载；Agent 不能重启宿主（会杀掉自己的会话） |

---

## 三、"复制工坊链接"这一步怎么做

1. 在 Steam 里打开那张壁纸的工坊页面（Wallpaper Engine → 创意工坊 → 打开该壁纸）。
2. 点右上角那排按钮里的 **分享（share）** —— 它就在 **"留言 / 评论"** 入口旁边。
3. 弹窗里的 **页面链接 / 复制链接** 就是这条 URL，一般点了就复制到剪贴板：

```
https://steamcommunity.com/sharedfiles/filedetails/?id=3814486439
                                                    ^^^^^^^^ 这就是 publishedFileId
```

4. 把它粘贴给 Agent。也可以在浏览器打开该页面，直接复制地址栏里的同一串。

> 想更省事：本目录提供 `scripts/copy-workshop-url.ps1 -PublishedFileId <id>`，
> 它直接用 Steam 官方 WebAPI 取出规范链接并放进剪贴板（**不需要**能访问 steamcommunity.com）。

---

## 四、手动安装（不用 Agent）

```powershell
git clone https://github.com/sysu-xyh/sysu-xyh2026.git "$env:TEMP\sysu-repo"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\sysu-repo\skills\dsh-desktop-wallpaper\scripts\bootstrap.ps1"
```
参数：`-DshHome`（默认 `$env:DSH_HOME`）、`-InstallDir`（默认 `%LOCALAPPDATA%\dsh-wallpaper\plugin`）、
`-ProfileName`（默认 `desktop`）、`-NoSkillLink`、`-NoVideoTask`。

---

## 五、装完怎么用

| 动作 | 怎么做 |
|---|---|
| 看壁纸 | 正常启动 Harness（桌面/开始菜单图标），左下角出现 `wallpaper ON · live <W>x<H>` |
| 开关壁纸 | 点左下角那个胶囊（关闭会精确还原原来的不透明界面） |
| 换壁纸 | 让 Agent 走"复制链接 → 定位 → 改 `client.js` 的 `VIDEO_URL`" |
| 调节透明度 | 改 `client.js` 里 `ON_CSS` 的三个 alpha（`_frame` / `_sidebarCol` / `_centerCol`） |

---

## 六、卸载

1. 从 `<dshHome>\profiles\<profile>\package.json` 删掉 `@local/dsh-wallpaper-live`（依赖与 bundles 两处）；
2. 删掉同目录 `node_modules\@local\dsh-wallpaper-live`；
3. 删掉 `%LOCALAPPDATA%\dsh-wallpaper`（插件与素材）；
4. 删掉 `$DSH_HOME\skills\dsh-desktop-wallpaper` 链接；
5. 需要时删掉计划任务 `DSH Wallpaper Video Server`。

**Harness 本体从未被修改**（`app.asar` 原样），所以不需要修复安装。

---

## 七、出问题先看这三处

| 症状 | 检查 |
|---|---|
| 完全没有壁纸 | `node -e "import('@local/dsh-wallpaper-live')"` 在 profile 目录里能否通过（不行就是安装/路径问题） |
| 有胶囊但画面不动 | 本地视频服务是否在跑（`http://127.0.0.1:8787/wallpaper.mp4`）、`client.js` 的 `VIDEO_URL` 是否指向真实文件 |
| 壁纸被界面挡住 | 面板用的是**硬编码颜色**，用的是 `[class*="_frame"]` 那套覆盖，不要只改 `--dsw-alias-*` 变量 |

更多失败案例与判定方法见 [reference/failure-modes.md](reference/failure-modes.md)。

---

## 八、给 Agent 的边界（重要）

- **不要**替用户下载或搬运受版权保护的壁纸文件；引导用户在 Steam 订阅。
- **不要**改 Harness 的安装文件（`app.asar` 等）——历史上这么做过，直接白屏。
- 遇到 skill 未覆盖的问题并解决后，按 [reference/field-notes/README.md](reference/field-notes/README.md)
  写现场记录并**只做本地提交**；**永远不要 `git push`**（公开历史不可撤销）。