/**
 * Browser half: paints the wallpaper behind the Harness Web UI.
 *
 * The shell's layout surfaces use HARD-CODED colours (rgb(27,27,28) frame/sidebar,
 * rgb(21,21,23) centre column), not the --dsw-alias-* tokens, so token overrides alone
 * leave the UI opaque. While the wallpaper is ON we therefore make those measured
 * surfaces translucent with attribute selectors that survive build-hash changes, and
 * raise the scrim so text stays readable. Toggling off removes every injected rule.
 *
 * Playback: the window should be launched with --autoplay-policy=no-user-gesture-required
 * (see scripts/bootstrap.ps1). If the policy still blocks play(), the retry ladder below
 * resumes on the first pointer/key event and reports the state in the pill.
 */
window.__ModuleLoader__.load({
  id: '@local/dsh-wallpaper-live',
  factory(require) {
    'use strict';

    var VIDEO_URL = 'http://127.0.0.1:8787/wallpaper.mp4';
    var POSTER_URL = 'http://127.0.0.1:8787/wallpaper.webp';

    var LAYER_CSS =
      'html{background-color:#05070c !important}' +
      '#dsh-live-wallpaper{position:fixed;inset:0;z-index:-1;pointer-events:none;overflow:hidden;background:#05070c}' +
      '#dsh-live-wallpaper video,#dsh-live-wallpaper img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;display:block}' +
      '#dsh-live-wallpaper .scrim{position:absolute;inset:0;' +
      'background:linear-gradient(90deg, rgba(4,6,11,.34) 0%, rgba(4,6,11,.20) 40%, rgba(4,6,11,.10) 70%, rgba(4,6,11,.22) 100%),' +
      'linear-gradient(180deg, rgba(4,6,11,.30) 0%, rgba(4,6,11,.06) 22%, rgba(4,6,11,.08) 72%, rgba(4,6,11,.40) 100%)}';

    var ON_CSS =
      'html,body{background:transparent !important}' +
      '[class*="_frame"]{background-color:rgba(27,27,28,.42) !important}' +
      '[class*="_sidebarCol"]{background-color:rgba(27,27,28,.40) !important}' +
      '[class*="_centerCol"]{background-color:rgba(21,21,23,.34) !important}' +
      '[class*="_root"]{background-color:transparent !important}' +
      '[class*="_emptyTabHost"]{background-color:transparent !important}' +
      ':root{--dsw-alias-bg-base:rgba(5,7,12,.45) !important;' +
      '--dsw-alias-bg-layer-1:rgba(9,12,19,.55) !important;' +
      '--dsw-alias-bg-layer-2:rgba(11,14,22,.70) !important}';

    var PILL_CSS =
      '#dsh-wallpaper-pill{position:fixed;left:10px;bottom:10px;z-index:2147483000;' +
      'display:flex;align-items:center;gap:6px;padding:5px 9px;border-radius:999px;' +
      'background:rgba(8,10,16,.82);border:1px solid rgba(120,170,255,.35);color:#cfe3ff;' +
      'font:11px/1.4 ui-monospace,Consolas,monospace;cursor:pointer;user-select:none;' +
      'backdrop-filter:blur(4px)}' +
      '#dsh-wallpaper-pill:hover{background:rgba(14,18,28,.92)}' +
      '#dsh-wallpaper-pill b{color:#8fd0ff;font-weight:600}';

    return {
      inject: [],
      apply(ctx) {
        var layer = null, layerStyle = null, onStyle = null, pillStyleEl = null, pill = null;
        var video = null, poster = null, retryTimer = null, gestureHooked = false;
        var disposed = false, on = true, state = 'init';

        function log() { console.log.apply(console, ['[dsh-wallpaper]'].concat([].slice.call(arguments))); }

        function ensureOnStyle() {
          if (!onStyle) {
            onStyle = document.createElement('style');
            onStyle.id = 'dsh-live-wallpaper-on';
            onStyle.textContent = ON_CSS;
            (document.head || document.documentElement).appendChild(onStyle);
          }
        }
        function dropOnStyle() {
          if (onStyle && onStyle.parentNode) onStyle.parentNode.removeChild(onStyle);
          onStyle = null;
        }

        function paint() {
          if (!pill) return;
          var view = video && video.readyState >= 3
            ? (video.videoWidth + 'x' + video.videoHeight)
            : (state === 'blocked' ? 'autoplay blocked' : 'loading');
          var suffix = state === 'blocked' ? ' - click anywhere' : (state === 'source' ? ' - video source down' : '');
          pill.innerHTML = '<b>wallpaper</b> ' + (on ? 'ON' : 'OFF') + (on ? ' \u00b7 ' + view + suffix : ' (click)') + (on ? ' (click)' : '');
        }

        function ensurePill() {
          if (pill || !document.body) return;
          pillStyleEl = document.createElement('style');
          pillStyleEl.id = 'dsh-live-wallpaper-pill-style';
          pillStyleEl.textContent = PILL_CSS;
          (document.head || document.documentElement).appendChild(pillStyleEl);
          pill = document.createElement('div');
          pill.id = 'dsh-wallpaper-pill';
          pill.title = 'click to toggle the Harness wallpaper';
          pill.addEventListener('click', function () { if (on) turnOff(); else turnOn(); });
          document.body.appendChild(pill);
          paint();
        }

        // ---------------- playback with a gesture fallback ----------------
        function tryPlay(reason) {
          if (disposed || !video || !on) return;
          var p = video.play();
          if (!p || !p.then) { state = 'playing'; paint(); return; }
          p.then(function () {
            state = 'playing';
            paint();
            log('playing (' + reason + ')');
          }).catch(function (err) {
            // A failed source (server down / 404) also rejects play(); that is NOT an
            // autoplay problem, so classify it separately instead of crying "blocked".
            var srcFailed = !!(video && video.error) || (video && video.networkState === 3);
            state = srcFailed ? 'source' : 'blocked';
            paint();
            log('play() rejected (' + reason + '): ' + (err && err.name) + ' ' + (err && err.message) +
                (srcFailed ? ' | media error code ' + (video.error ? video.error.code : '?') +
                  ' - the video source is unavailable (is the server on 127.0.0.1:8787 running?)'
                : ' | muted=' + video.muted + ' volume=' + video.volume));
            hookGesture();
            // keep trying quietly: a policy change or a later gesture may unblock it
            if (retryTimer) clearInterval(retryTimer);
            var n = 0;
            retryTimer = setInterval(function () {
              n += 1;
              if (disposed || n > 40) { clearInterval(retryTimer); retryTimer = null; return; }
              if (!video.paused || !on) { clearInterval(retryTimer); retryTimer = null; return; }
              video.play().then(function () { state = 'playing'; paint(); clearInterval(retryTimer); retryTimer = null; }).catch(function () {});
            }, 1500);
          });
        }

        function hookGesture() {
          if (gestureHooked) return;
          gestureHooked = true;
          var resume = function () {
            if (disposed) return;
            log('user gesture seen; resuming playback');
            tryPlay('gesture');
            document.removeEventListener('pointerdown', resume, true);
            document.removeEventListener('keydown', resume, true);
            document.removeEventListener('wheel', resume, true);
          };
          document.addEventListener('pointerdown', resume, true);
          document.addEventListener('keydown', resume, true);
          document.addEventListener('wheel', resume, true);
        }

        function turnOn() {
          on = true;
          if (layer) layer.style.display = '';
          ensureOnStyle();
          tryPlay('toggle-on');
        }
        function turnOff() {
          on = false;
          if (layer) layer.style.display = 'none';
          if (video) { try { video.pause(); } catch (e) {} }
          if (retryTimer) { clearInterval(retryTimer); retryTimer = null; }
          dropOnStyle();
          paint();
        }

        function build() {
          if (document.getElementById('dsh-live-wallpaper')) return;
          var host = document.body || document.documentElement;

          layerStyle = document.createElement('style');
          layerStyle.id = 'dsh-live-wallpaper-style';
          layerStyle.textContent = LAYER_CSS;
          (document.head || document.documentElement).appendChild(layerStyle);

          layer = document.createElement('div');
          layer.id = 'dsh-live-wallpaper';

          poster = document.createElement('img');
          poster.src = POSTER_URL;
          poster.alt = '';
          poster.setAttribute('aria-hidden', 'true');
          poster.addEventListener('error', function () { poster.remove(); }, { once: true });

          video = document.createElement('video');
          video.src = VIDEO_URL;
          video.muted = true;             // required for autoplay
          video.defaultMuted = true;
          video.volume = 0;
          video.loop = true;
          video.autoplay = true;
          video.playsInline = true;
          video.preload = 'auto';
          video.setAttribute('muted', '');
          video.setAttribute('playsinline', '');
          video.setAttribute('webkit-playsinline', '');
          video.setAttribute('disablepictureinpicture', '');
          video.setAttribute('aria-hidden', 'true');

          var scrim = document.createElement('div');
          scrim.className = 'scrim';
          scrim.setAttribute('aria-hidden', 'true');

          layer.appendChild(poster);
          layer.appendChild(video);
          layer.appendChild(scrim);
          if (host.firstChild) host.insertBefore(layer, host.firstChild);
          else host.appendChild(layer);

          video.addEventListener('canplay', function () {
            log('video ready ' + video.videoWidth + 'x' + video.videoHeight + ' readyState ' + video.readyState);
            paint();
            tryPlay('canplay');
          }, { once: true });
          video.addEventListener('playing', function () { state = 'playing'; paint(); });
          video.addEventListener('error', function () {
            state = 'failed';
            log('video ERROR code ' + (video.error ? video.error.code : '?') + ' - is the server on 127.0.0.1:8787?');
            paint();
          }, { once: true });

          ensureOnStyle();
          tryPlay('build');
          log('layer inserted into ' + (host === document.body ? '<body>' : '<html>'));
        }

        function teardown() {
          disposed = true;
          if (retryTimer) clearInterval(retryTimer);
          dropOnStyle();
          if (video) { try { video.pause(); } catch (e) {} video.removeAttribute('src'); video.load(); }
          [layer, layerStyle, pillStyleEl, pill].forEach(function (el) {
            if (el && el.parentNode) el.parentNode.removeChild(el);
          });
          layer = layerStyle = pillStyleEl = pill = video = poster = null;
        }

        function start() {
          if (disposed) return;
          if (!document.body) { setTimeout(start, 30); return; }
          build();
          ensurePill();
        }

        if (document.readyState === 'loading') {
          document.addEventListener('DOMContentLoaded', start, { once: true });
        } else {
          start();
        }

        // NOTE: deliberately NO ctx.effect(teardown) here: the app releases this client
        // entry shortly after activation, and a teardown effect would remove the layer.
        log('live wallpaper v1.6 installed; readyState = ' + document.readyState);
      },
    };
  },
});