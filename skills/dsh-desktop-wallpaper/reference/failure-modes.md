# 各失败方案的实测现象与判定方法

本文件记录的都是**实际发生过的结果**，不是推测。每条都给出“怎么判定它失败了”，方便后来者快速排除。

---

## 1. 直接修改 `app.asar`（替换前端资源字节）

**做法**：把壁纸以 base64 数据 URL 注入前端 `index-*.css` / `vendor-*.js`，用等长替换（不改变 asar 头部与偏移）。

**现象**：应用**启动即白屏**；用户不得不重装组件才恢复。

**原因**：`vendor-*.js` 是 Vite 预打包模块，文件尾部可能仍属于某个模块的数据；替换尾部字节破坏了模块结构，页面初始化抛错。

**判定**：改动后窗口白屏 / 渲染器报模块解析错误。

**结论**：不要用。壁纸这种纯视觉需求绝不值得改应用自身的安装文件。

---

## 2. 浏览器用户脚本（Tampermonkey）

**做法**：写 userscript，匹配 `http://127.0.0.1:19387/*`，注入视频层。

**现象**：桌面窗口里毫无效果。

**原因**：桌面窗口是 Electron 自定义协议页面 `dsh-app://app/`，**不运行浏览器扩展**。user-script 只在真实浏览器里生效。

**判定**：渲染器里 `location.href` 是 `dsh-app://app/`（而不是 `http://127.0.0.1:19387/`）。

**附注**：如果用户**愿意改用浏览器**打开同一个 UI（`dsh web ... ` 打印的 `http://127.0.0.1:<port>/?token=...`），用户脚本这条路是可行且已实测的（视频 4K H.264 正常播放、循环、`z-index:-1` 叠加正确）。但它需要用户换工作窗口。

---

## 3. Chrome/Edge 扩展（`--load-extension`）

**做法**：MV3 扩展 + content script + `web_accessible_resources`（自带 mp4），启动参数加 `--load-extension=<dir>`。

**现象**：扩展本身没问题（在普通 `http` 页面上实测成功：图层注入、`video` 3840x2160 播放、CSS 生效、胶囊正常）。但在 DSH 窗口里**完全不注入**。

**判定**（在 DSH 窗口的渲染器里执行）：

```js
!!document.getElementById('<扩展注入的节点 id>')     // false
typeof chrome !== 'undefined' && !!chrome.runtime    // false  <- 关键
```

**原因**：Chromium 扩展的 content script 默认不注入自定义协议（非 http/https/file）页面。

**结论**：只要目标窗口是 `dsh-app://`，扩展方案不可行。启动参数加上后进程命令行里确实能看到 `--load-extension`，所以"参数没生效"不是原因，别在这上面浪费时间。

---

## 4. 调试端口 + 外部注入器（DevTools 协议 agent）

**做法**：DSH 以 `--remote-debugging-port=9222` 启动；外部 Node 进程连 CDP，往页面里注入图层（并每 3 秒巡检自愈）。

**效果**：**能稳定工作**（实测：注入后 6s/14s 仍在，视频时间轴推进；故意删除图层后 3 秒内自动补回）。

**但它有三个硬伤**：

1. **端口必须在启动那一刻给**，事后加不了 → 用户"自己点图标启动"的实例没有端口，注入器连不上，壁纸必然不出现。
2. 于是就会演化出"必须用专用启动器启动"或"检测到没端口就重启应用"的怪行为 —— 用户明确反感。
3. **自动化重启应用会杀掉调用者自己的会话**：如果你（AI/脚本）就在那个应用里跑命令，`taskkill` 会把自己的执行环境一起杀掉，命令永远拿不到结果（本项目的多次失败都源于此）。

**若确需调试**：把"杀应用 + 重启 + 探测"放进**独立于调用者进程树的计划任务**（`Register-ScheduledTask` + `Start-ScheduledTask`），不要直接 `taskkill`；并且**工作目录**要设对，否则会得到误导性的 `ERR_MODULE_NOT_FOUND`（Electron 用 `ELECTRON_RUN_AS_NODE=1` 跑 `-e` 时，解析基准是当前工作目录，不是脚本所在目录）。

---

## 5. 通过插件面板“添加插件 → 输入本地目录”

**做法**：在插件页填入本地插件目录，点安装。

**现象**：有时 profile 的 `package.json` 里写出了依赖，但 `node_modules/@local/<pkg>` **没有正确链接**（或链接指向了后来不可用的路径）；重启后启动报：

```
web boot: 1 entry did not activate
@local/<pkg>: failed
```

**判定**：命令行复现最快 ——

```powershell
cd $env:DSH_HOME\profiles\desktop
node -e "import('@local/<pkg>').then(m=>console.log('OK')).catch(e=>console.log('FAIL',e.code,e.message))"
```

`FAIL ERR_MODULE_NOT_FOUND` / `failed to import` 就是链接/路径问题，不是插件代码问题。

**对策**：用 `scripts/install-plugin.ps1`（它会同时处理依赖、bundles、junction、lock 四处并自检）。

---

## 6. 插件装了、代码也跑了，但图层几秒后消失

**现象**（最迷惑人的一条）：

```
[dsh-wallpaper] layer inserted into <body> | body children 4
[dsh-wallpaper] live wallpaper v1.3 installed; readyState = complete
layer: false                      <- 但图层不在
```

且用 `MutationObserver` 监听 DOM，**没有任何移除记录**。

**原因**：应用启动流程会**释放**这个客户端条目 → 触发插件的 `ctx.effect(teardown)` → 图层被插件自己的清理逻辑移除。Observer 抓不到，是因为移除发生在插件的清理函数里（属于"我们自己的代码"），不是外部 DOM 操作。

**判定**：插件里注册过 `ctx.effect(...)`；日志尾行打印了、图层却没了。

**对策**：**不要注册 teardown**，让图层独立于插件生命周期（用胶囊按钮/刷新页面来关闭）。

---

## 7. 壁纸被不透明界面挡住

**现象**：图层与视频都正常（日志、`video.currentTime` 都在推进），但肉眼看不出壁纸。

**原因**：界面面板用的是**硬编码颜色**，不是 `--dsw-alias-*` 变量：

| 节点类名 | 背景 |
|---|---|
| `*_frame*` | `rgb(27,27,28)` |
| `*_sidebarCol*` | `rgb(27,27,28)` |
| `*_centerCol*` / `*_root*` | `rgb(21,21,23)` |

只改 CSS 变量是**无效**的（实测：变量确实变成了 `rgba(5,7,12,.55)`，但面板颜色没变）。

**判定**：在渲染器里枚举大面积元素的计算样式，找出 `backgroundColor` 不透明的节点。

**对策**：用 `[class*="_frame"]` 这类属性选择器覆盖（构建哈希会变，别写死完整类名），并配合暗角渐变保证文字可读。

---

## 8. 拔掉可移动盘后壁纸消失

**现象**：盘在时一切正常；拔盘重启后没有壁纸，也不报错（只是没有）。

**原因**：profile 的依赖是 `link:<插件目录>`，而插件目录在可移动盘上 → 模块解析失败。

**判定**：

```powershell
Get-Item "$env:DSH_HOME\profiles\desktop\node_modules\@local\<pkg>" | Select-Object LinkType,Target
```

Target 指向可移动盘 = 隐患。

**对策**：插件目录放在固定本地盘，并同步修正 `package.json`(依赖)、junction、`pnpm-lock.yaml` 三处。