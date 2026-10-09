/**
 * Browser half: paints the wallpaper behind the Harness Web UI.
 *
 * The shell's layout surfaces use HARD-CODED colours (rgb(27,27,28) frame/sidebar,
 * rgb(21,21,23) centre column), not the --dsw-alias-* tokens, so token overrides alone
 * leave the UI opaque. While the wallpaper is ON we therefore make those measured
 * surfaces translucent with attribute selectors that survive build-hash changes, and
 * raise the scrim so text stays readable. Toggling off removes every injected rule,
 * restoring the original look exactly.
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
        var video = null, poster = null, retries = 0, retryTimer = null, disposed = false, on = true;

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
        function paint(msg) {
          if (!pill) return;
          pill.innerHTML = '<b>wallpaper</b> ' + (on ? 'ON' : 'OFF') + (msg ? ' · ' + msg : '') + ' (click)';
        }

        function turnOn() {
          on = true;
          if (layer) layer.style.display = '';
          ensureOnStyle();
          if (video) kick();
          paint(video && video.readyState >= 3 ? 'live ' + video.videoWidth + 'x' + video.videoHeight : 'loading');
        }
        function turnOff() {
          on = false;
          if (layer) layer.style.display = 'none';
          if (video) { try { video.pause(); } catch (e) {} }
          dropOnStyle();
          paint('video paused · UI restored');
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
          video.muted = true;
          video.defaultMuted = true;
          video.loop = true;
          video.autoplay = true;
          video.playsInline = true;
          video.preload = 'auto';
          video.setAttribute('muted', '');
          video.setAttribute('playsinline', '');
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
            log('video ready', video.videoWidth + 'x' + video.videoHeight, 'readyState', video.readyState);
            paint('live ' + video.videoWidth + 'x' + video.videoHeight);
          }, { once: true });
          video.addEventListener('error', function () {
            log('video ERROR code', video.error ? video.error.code : '?', '- is the server on 127.0.0.1:8787?');
            paint('video failed c' + (video.error ? video.error.code : '?'));
          }, { once: true });

          ensureOnStyle();
          kick();
          log('layer inserted into', host === document.body ? '<body>' : '<html>', '| body children', document.body ? document.body.children.length : -1);
        }

        function kick() {
          if (disposed || !video) return;
          var p = video.play();
          if (p && p.catch) {
            p.catch(function (err) {
              retries += 1;
              if (retries <= 30) retryTimer = setTimeout(kick, 800);
              else { log('autoplay blocked:', err && err.message); paint('autoplay blocked'); }
            });
          }
        }

        function teardown() {
          // kept for reference only; the wallpaper is deliberately NOT torn down by the
          // plugin lifecycle (see the note where ctx.effect used to be registered).
          disposed = true;
          if (retryTimer) clearTimeout(retryTimer);
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
          paint(video && video.readyState >= 3 ? 'live' : 'loading');
        }

        if (document.readyState === 'loading') {
          document.addEventListener('DOMContentLoaded', start, { once: true });
        } else {
          start();
        }

        // NOTE: deliberately NO ctx.effect(teardown) here.
        // The app's web boot disposes this client entry shortly after activation, and a
        // teardown effect would remove the wallpaper layer again a few seconds after it
        // appears (observed: "layer inserted" logged, then the layer gone with no
        // MutationObserver record). The wallpaper is therefore intentionally independent
        // of the plugin lifecycle: it is removed by reloading the window, and toggled by
        // the pill. This is what makes the wallpaper appear on a NORMAL app start.
        log('live wallpaper v1.4 installed; readyState =', document.readyState);
      },
    };
  },
});