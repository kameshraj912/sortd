// Tiny timeline engine for the Sortd Reels.
// Every element's look at time t is computed from its tweens, so any frame
// can be rendered on its own (the renderer calls seek(t) for each frame).
(function () {
  const E = {
    lin: k => k,
    out: k => 1 - Math.pow(1 - k, 3),
    inout: k => (k < .5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2),
    in: k => k * k * k,
    back: k => { const c = 1.9, d = c + 1; return 1 + d * Math.pow(k - 1, 3) + c * Math.pow(k - 1, 2); },
  };
  const BASE = { o: 1, x: 0, y: 0, s: 1, r: 0, b: 0, h: null };
  const tracks = new Map(); // element -> tweens
  const hooks = [];

  // tw(selector, t0, t1, to, from?, ease?)
  window.tw = (sel, t0, t1, to, from = {}, ease = 'out') => {
    document.querySelectorAll(sel).forEach(el => {
      if (!tracks.has(el)) tracks.set(el, []);
      tracks.get(el).push({ t0, t1, to, from, ease: E[ease] || E.out });
    });
  };
  // Appear at tin, leave at tout. enter: 'up' | 'down' | 'pop' | 'fade' | 'cut'
  window.show = (sel, tin, tout, enter = 'up', leave = 'fade') => {
    const d = enter === 'cut' ? 0.001 : 0.45;
    const from = { o: 0 };
    if (enter === 'up') from.y = 28;
    if (enter === 'down') from.y = -120;
    if (enter === 'pop') from.s = 0.7;
    tw(sel, tin, tin + d, { o: 1, y: 0, s: 1 }, from, enter === 'pop' || enter === 'down' ? 'back' : 'out');
    if (tout != null) tw(sel, tout, tout + (leave === 'cut' ? 0.001 : 0.3), { o: 0 }, {}, 'lin');
  };
  window.onFrame = fn => hooks.push(fn);

  function valueAt(list, p, t) {
    let v = BASE[p], set = false;
    for (const w of list) {
      if (!(p in w.to)) continue;
      if (t < w.t0) { if (!set && p in w.from) v = w.from[p]; break; }
      if (t < w.t1) {
        const f = p in w.from ? w.from[p] : v;
        v = f + (w.to[p] - f) * w.ease((t - w.t0) / (w.t1 - w.t0));
        set = true; break;
      }
      v = w.to[p]; set = true;
    }
    return v;
  }

  window.seek = t => {
    for (const [el, list] of tracks) {
      list.sort((a, b) => a.t0 - b.t0);
      const o = valueAt(list, 'o', t), x = valueAt(list, 'x', t), y = valueAt(list, 'y', t);
      const s = valueAt(list, 's', t), r = valueAt(list, 'r', t), b = valueAt(list, 'b', t), h = valueAt(list, 'h', t);
      el.style.opacity = o;
      el.style.visibility = o <= 0.001 ? 'hidden' : 'visible';
      el.style.transform = `translate(${x}px, ${y}px) scale(${s}) rotate(${r}deg)`;
      el.style.filter = b ? `blur(${b}px)` : '';
      if (h !== null) el.style.height = h + 'px';
    }
    hooks.forEach(fn => fn(t));
  };

  // Shared end card: dark panel, colour glows, icon, wordmark, one line, CTA.
  window.endCard = (t0, line) => {
    const d = document.createElement('div');
    d.className = 'end';
    d.innerHTML = `<div class="glow"></div>
      <img class="e-icon" src="assets/AppIcon.png" alt="">
      <div class="e-word"><b>sortd</b><div class="wbars"><i></i><i></i><i></i><i></i></div></div>
      <p class="e-line">${line}</p>
      <p class="e-cta">In beta. Link in bio.</p>
      <p class="e-url">sortd.page</p>`;
    document.getElementById('stage').appendChild(d);
    show('.end', t0, null, 'fade');
    show('.end .e-icon', t0 + .15, null, 'pop');
    show('.end .e-word', t0 + .3, null, 'up');
    show('.end .e-line', t0 + .55, null, 'up');
    show('.end .e-cta', t0 + .85, null, 'up');
    show('.end .e-url', t0 + 1.0, null, 'fade');
  };
})();
