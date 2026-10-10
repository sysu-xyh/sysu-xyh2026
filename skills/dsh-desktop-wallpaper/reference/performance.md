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

## 附：末尾"卡一下"的第二个原因——容器时长比画面长

即使分辨率降到 1080p，若**容器时长 > 实际画面时长**，播放到末尾会**冻结最后一帧**再跳回开头，
观感就是"最后一两秒不流畅"。本项目的实测数据：

| | 帧数 | 帧间隔 | 末帧时间 | 容器时长 | 尾部冻结 |
|---|---|---|---|---|---|
| 工坊原始 4K120 | 821 | 恒 8.33ms | 6.8333 | **7.050** | 有 ~0.2s |
| 转码 1080p60（未处理） | 411 | 恒 16.67ms | 6.8333 | **6.850** | 有 ~0.02s + 多一帧 |
| 转码 1080p60（修复后） | 410 | 恒 16.67ms | 6.8167 | **6.8333** | **无** |

判定方法（看"末帧时间 + 一帧"是否等于"容器时长"）：

```powershell
ffprobe -v error -select_streams v:0 -count_frames `
  -show_entries stream=nb_read_frames,r_frame_rate -show_entries format=duration `
  -of default=noprint_wrappers=1 <文件>
# 再用 -show_entries frame=pts_time -of csv=p=0 取末帧时间
```

修复：**别让滤镜多补一帧，并把帧数钉死**：

```powershell
ffmpeg -hide_banner -y -i <源> -an `
  -vf "fps=60,scale=1920:1080:flags=lanczos" `
  -frames:v 410 `                    # = floor(末帧时间 × 目标fps) + 1，去掉尾部补帧
  -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -movflags +faststart <输出>
```

（本例 6.8333 × 60 = 410 帧；输出时长 6.8333s = 410/60，精确闭合。）

## 附：最后一个常被归因于"卡"的现象——循环接缝

壁纸是**循环播放**的，作者没做无缝循环时，最后一帧接回第一帧会有一次"跳"。
先按上面的方法排除"尾部冻结"，如果接缝仍然明显，再考虑：

- 裁掉尾部与首帧几乎相同的一段（往往能自然衔接）；
- 或在接缝处做 0.2–0.4s 的交叉淡化（会略微改变观感，且需要更复杂的滤镜图）。

