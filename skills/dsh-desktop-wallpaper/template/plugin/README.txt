DSH 客户端插件模板（可直接安装）

包名：@local/dsh-wallpaper-live
文件：package.json / cordis.patch.yml / index.js / client.js

安装（推荐用脚本，它会处理依赖+bundles+junction+lock 四处并自检）：
  powershell -NoProfile -ExecutionPolicy Bypass -File ..\..\scripts\install-plugin.ps1 -PluginDir .

手工安装要点：
  1) profile 的 package.json 里 dependencies 与 dsh.profile.bundles 两处都要有本包名
  2) node_modules/@local/dsh-wallpaper-live 必须是指向本目录（固定本地盘）的 junction
  3) 若 pnpm-lock.yaml 里残留别的路径，一并改成实际路径

改壁纸内容：编辑 client.js
  VIDEO_URL / POSTER_URL  -> 视频与封面地址
  ON_CSS                  -> 界面半透明程度（_frame / _sidebarCol / _centerCol 三个 alpha）

注意：client.js 里**故意没有** ctx.effect(teardown)；请勿加回，否则图层会在应用启动后被撤掉。