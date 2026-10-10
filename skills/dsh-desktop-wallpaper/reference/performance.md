# 性能：4K 视频当背景会卡（以及怎么修）

## 症状

壁纸能显示、视频在播放，但**明显卡顿/掉帧**，鼠标移动或滚动窗口时更明显。

## 先量化，不要凭感觉

用 Chromium 自带的播放质量统计，直接读出"丢了多少帧"（在渲染器里执行）：

```js
const v = document.querySelector('#dsh-live-wallpaper video');
await new Promise((r) => setTimeout(r, 6000));
const q = v.getVideoPlaybackQuality();
({ res: v.videoWidth + 'x' + v.videoHeight, total: q.totalVideoFrames, dropped: q.droppedVideoFrames,
   dropPct: +(100 * q.droppedVideoFrames / q.totalVideoFrames).toFixed(1) });
```

本项目实测（同一段 7 秒素材、同一台机器）：

| 素材 | 分辨率/帧率 | 丢帧率 |
|---|---|---|
| 工坊原始文件 | 3840×2160 @120 fps, 17.4 Mbps, H.264 | **51.2%** |
| 转码后 | 1920×1080 @60 fps, 4.5 Mbps, H.264 | **4.2%** |

**丢帧率是判定"卡不卡"的客观指标**；`currentTime` 在推进并不代表流畅。

## 为什么会这样

背景播放要**持续解码并合成**，而 4K@120 每秒要解 **3.84M 像素 × 120 ≈ 4.6 亿像素**；
1080p@60 只有约 1.24 亿，**相差约 3.7 倍**（加上 120fps 的时间戳密度，合成开销更大）。
在 1080p 屏幕上，4K 的额外像素对观感几乎没有贡献，纯粹是浪费。

## 修法：转码成 1080p（推荐）

需要 `ffmpeg`。**没有也不要紧**——本项目实测用 winget 便携下载即可，无需管理员、不改 PATH：

```powershell
# 下载（不安装）到本地目录，然后解压取出 ffmpeg.exe
winget download --id BtbN.FFmpeg.GPL --accept-source-agreements --accept-package-agreements --download-directory D:\dsh-wallpaper\tools
Expand-Archive -Path D:\dsh-wallpaper\tools\*.zip -DestinationPath D:\dsh-wallpaper\tools\_x -Force
Copy-Item (Get-ChildItem D:\dsh-wallpaper\tools\_x -Recurse -Filter ffmpeg.exe | Select-Object -First 1).FullName D:\dsh-wallpaper\tools\
```

转码（保留原文件，输出去掉音轨）：

```powershell
ffmpeg -hide_banner -y -i <原始 4K 视频> -an `
  -vf "scale=1920:1080:flags=lanczos,fps=60" `
  -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -movflags +faststart `
  <输出>\wallpaper-1080p60.mp4
```

本项目实测：14.31 MB → **3.70 MB**，耗时 **17 秒**，丢帧率 51.2% → **4.2%**。

放好后让本地服务优先使用它（`optional/video-server/wallpaper-server.mjs` 已经按这个优先级找文件）：

```
assets/wallpaper-1080p60.mp4   <- 优先
wallpaper.mp4                  <- 本地通用副本
<工坊原始文件>                  <- 兜底
```

## 备选/叠加手段（按收益排序）

| 手段 | 预期收益 | 代价 |
|---|---|---|
| **降到 1080p60**（上面） | 丢帧率降一个数量级 | 需要 ffmpeg；画质几乎无感 |
| 降到 720p60 | 再降约 2 倍解码量 | 大屏上会明显发软 |
| 降到 30 fps（`fps=30`） | 再降一半 | 动态感变弱，但背景壁纸通常看不出来 |
| 用 `-preset` 更快/`-crf` 更高 | 文件更小 | 画质下降 |
| 缩短循环（只取最有代表性的 2–3 秒） | 文件更小、缓存友好 | 需要挑片段 |

## 静态封面也要放在本地

插件在视频未就绪/服务未起时显示封面。**封面图要和视频一样放在固定本地盘**，
不要指向可移动盘或临时目录——否则盘一拔就变黑屏（本项目踩过：封面曾指向 U 盘路径）。

## 提醒

- **不要在宿主应用内部执行会杀掉宿主的操作**（例如 `taskkill` 应用）——你会把自己的执行环境一起杀掉。
- 转码是**离线**动作，一次做好即可；运行时只涉及"服务读一个本地文件"。
