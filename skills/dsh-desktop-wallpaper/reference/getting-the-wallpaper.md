# 素材从哪来（Wallpaper Engine / Steam 创意工坊）

**本 skill 不附带任何壁纸素材。** `template/plugin/client.js` 里的 `VIDEO_URL` / `POSTER_URL`
是占位地址，必须由用户提供自己的素材。这样做既合规（不散布他人作品），也让用户能自由换壁纸。

> 面向 Agent：**不要**替用户去找、下载、搬运受版权保护的壁纸文件。正确做法是**引导用户自己完成**
> 下面 1-4 步，你只负责"定位本机已有文件 + 接进插件 + 校验"。

---

## 0. 先问用户三个问题

1. 壁纸是 **Wallpaper Engine** 上的（Steam 创意工坊）？还是本地现成的图片/视频？
2. 若来自创意工坊：**订阅了吗**？（订阅后 Steam 会把文件下到本地，不需要第三方下载站）
3. 内容类型：**视频壁纸**（`*.mp4` 等）、**静态图**、还是 **scene 工程**（`scene.pkg`）？

- 静态图 → 直接用作 `background-image`，跳到第 4 步。
- 视频 → 第 1-3 步 + 第 4 步。
- scene 工程 → **无法直接当视频用**，只能从作者页面/工程预览图取静态图，或让用户改选视频类壁纸。

---

## 1. 安装 Wallpaper Engine 客户端（免费）

Steam 商店里 **Wallpaper Engine** 的 *Wallpaper Engine – Wallpaper Engine*（AppID **431960**）
其中"壁纸引擎"本体是收费的，但**仅浏览/订阅壁纸**用 Steam 客户端即可；
若用户没有 Wallpaper Engine，也可让作者在工坊页面提供静态预览 —— 但**不要**引导去第三方下载站（版权与安全都不可靠）。

## 2. 订阅目标壁纸

在 Steam 客户端或工坊页面点 **订阅**。Steam 会立刻把内容下载到本地创意工坊缓存：

```
<SteamLibrary>\steamapps\workshop\content\431960\<publishedFileId>\
```

Steam 库可能有多个，用脚本自动找（见 `scripts/discover-wallpaper.ps1`），
或读 `<Steam>\steamapps\libraryfolders.vdf` 里的 `path` 字段。

## 3. 用脚本定位本机文件（推荐）

```powershell
# 只找：给定工坊 id，打印它下载到了哪里、里面有什么
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\discover-wallpaper.ps1 -PublishedFileId 3814486439

# 找 + 把视频复制到插件的素材目录，并打印可直接用的 URL
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\discover-wallpaper.ps1 -PublishedFileId 3814486439 -CopyTo D:\dsh-wallpaper\assets
```

脚本会：
1. 从 `steamapps/libraryfolders.vdf` 解析出所有库路径；
2. 在 `<lib>\steamapps\workshop\content\431960\<id>` 找内容；
3. 列出文件；若发现视频，报告时长/分辨率需要的信息，并（可选）复制成 `assets\wallpaper.mp4`；
4. 打印下一步该填什么。

**只订阅还是不下载？** 常见原因：Steam 未完成下载、该工坊项不是 431960（不是 Wallpaper Engine 壁纸）、
或用户用的是"仅订阅不下载"。让用户在 Steam 的"下载"页确认完成。

## 4. 元数据查询（不需要访问 steamcommunity.com）

有些网络环境打不开 `steamcommunity.com`，但 **Steam 官方 WebAPI 通常可用**：

```powershell
$body = 'itemcount=1&publishedfileids[0]=<publishedFileId>'
Invoke-RestMethod -Method Post -Uri 'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/' -Body $body |
  Select-Object -ExpandProperty response | Select-Object -ExpandProperty publishedfiledetails
```

返回里有用字段：
- `title` / `tags`（判断类型：`Video` / `Scene` / `Application`、分辨率）
- `preview_url`（**可直接当静态封面**；4K 版本可在 URL 后加 `?imw=3840&imh=2160&ima=fit&impolicy=Letterbox` 取更大图）
- `hcontent_file`（工坊内容哈希，**不能**直接拼成公开下载 URL）

> 这套接口是本项目实测可用的"无 VPN 取元数据"路径。工坊页面 HTML 在没有登录态时也**没有直链**，
> 所以不要试图从网页里抓下载地址。

## 5. 接进插件

**视频壁纸**：用 `optional/video-server/` 起本地服务（仅 `127.0.0.1:8787`），然后改
`template/plugin/client.js`：

```js
var VIDEO_URL = 'http://127.0.0.1:8787/wallpaper.mp4';
var POSTER_URL = 'http://127.0.0.1:8787/wallpaper.webp';   // 可选：静态封面（预览图）
```

**静态图**：直接把本地文件转成 data URL，或用一个可访问的本地地址，写进 `LAYER_CSS` 的 `background-image`。

> 若用户想要单帧画面（静态壁纸）而不是视频：可用平台自带的浏览器做"解码取帧"，不必依赖 ffmpeg ——
> 让 Edge/Chrome 以无头模式打开一个含 `<video>` 的本地页面，`seek` 后用 `canvas.drawImage` 导出 PNG。
> 注意：在无头浏览器里 `--screenshot` 对视频帧**不可靠**，要走 CDP 的 `Runtime.evaluate` + `canvas`。

## 6. 版权与开源注意事项

- **不要把第三方壁纸文件提交进仓库**（包括预览图）。仓库里只应保留插件代码与**占位 URL**。
- 在 README 里说明：素材由用户自行准备并自负合规责任。
- 若用户希望分发自己的壁纸，应遵守原作者在创意工坊页面声明的授权。
- 预览图（`preview_url`）同样是作者作品，仅限用户本机使用。

---

## 给 Agent 的检查清单

- [ ] 问清来源（创意工坊 / 本地文件）与类型（视频 / 静态 / scene）
- [ ] 确认用户**已订阅**、Steam 已下载完成（否则引导去 Steam 下载页，而不是去第三方站点）
- [ ] 用 `scripts/discover-wallpaper.ps1` 定位本机路径（不要手写猜测路径）
- [ ] 需要元数据/预览图时用 Steam WebAPI（`GetPublishedFileDetails`），不要抓工坊网页
- [ ] 把素材放进本机固定目录（**不要**放进插件目录以外会被清理的地方，也不要放可移动盘）
- [ ] 视频走本地 HTTP 服务；静态图直接注入；两者都保留"服务/素材缺失 → 只显示封面"的降级
- [ ] 不把任何第三方素材复制进要开源的仓库