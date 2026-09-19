// Sortd Money website: light/dark switch and gentle scroll-in. Loaded in <head> so the
// chosen theme is applied before the page paints (no flash).
(function () {
  try { console.log("%csortd", "font:800 28px -apple-system,sans-serif;letter-spacing:-1px", "\nReading the source? Respect.\nNo trackers in here, promise. Check the Network tab.\nWe're not hiring (it's one person), but say hi: support@sortd.page"); } catch (e) {}
  var root = document.documentElement;
  var key = "sortd-theme";
  function saved() { try { return localStorage.getItem(key); } catch (e) { return null; } }
  function save(v) { try { v === "system" ? localStorage.removeItem(key) : localStorage.setItem(key, v); } catch (e) {} }
  function apply(mode) {
    if (mode === "light" || mode === "dark") root.setAttribute("data-theme", mode);
    else root.removeAttribute("data-theme");
  }
  var mode = saved() || "system";
  apply(mode);
  root.classList.add("js");

  document.addEventListener("DOMContentLoaded", function () {
    // Theme button cycles System → Light → Dark.
    var btn = document.querySelector(".theme-btn");
    var names = { system: "Theme: match device", light: "Theme: light", dark: "Theme: dark" };
    function sync() { if (btn) { btn.dataset.mode = mode; btn.setAttribute("aria-label", names[mode]); btn.title = names[mode]; } }
    sync();
    if (btn) btn.addEventListener("click", function () {
      mode = mode === "system" ? "light" : mode === "light" ? "dark" : "system";
      apply(mode); save(mode); sync();
    });

    // Feature tour tabs (arrow keys move between them).
    var tabs = [].slice.call(document.querySelectorAll('.tabs [role="tab"]'));
    function select(t, focus) {
      tabs.forEach(function (x) {
        var on = x === t;
        x.setAttribute("aria-selected", on ? "true" : "false");
        x.tabIndex = on ? 0 : -1;
        document.getElementById(x.getAttribute("aria-controls")).hidden = !on;
      });
      if (focus) t.focus();
    }
    tabs.forEach(function (t, i) {
      t.addEventListener("click", function () { select(t, false); });
      t.addEventListener("keydown", function (e) {
        if (e.key === "ArrowRight") { e.preventDefault(); select(tabs[(i + 1) % tabs.length], true); }
        if (e.key === "ArrowLeft") { e.preventDefault(); select(tabs[(i - 1 + tabs.length) % tabs.length], true); }
      });
    });

    // ---- Easter eggs ----
    function toast(msg) {
      var old = document.querySelector(".toast"); if (old) old.remove();
      var t = document.createElement("div"); t.className = "toast"; t.setAttribute("role", "status"); t.textContent = msg;
      document.body.appendChild(t); requestAnimationFrame(function () { t.classList.add("show"); });
      setTimeout(function () { t.classList.remove("show"); setTimeout(function () { t.remove(); }, 500); }, 3200);
    }
    var calm = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    // Hover notes: on touch screens a tap shows them as a pop-up instead.
    document.querySelectorAll(".egg").forEach(function (el) {
      el.addEventListener("click", function () { if (window.matchMedia("(hover: none)").matches) toast(el.dataset.egg); });
    });
    // Tap the logo five times.
    var taps = 0, tapTimer;
    var logo = document.querySelector(".site-header .brand");
    if (logo) logo.addEventListener("click", function (e) {
      taps++; clearTimeout(tapTimer); tapTimer = setTimeout(function () { taps = 0; }, 1500);
      if (taps >= 5) { e.preventDefault(); taps = 0; toast("Five taps. More than you've checked your budget this month."); }
      else if (taps > 1) e.preventDefault();
    });
    // ↑ ↑ ↓ ↓ ← → ← → B A
    var code = ["ArrowUp","ArrowUp","ArrowDown","ArrowDown","ArrowLeft","ArrowRight","ArrowLeft","ArrowRight","b","a"], pos = 0;
    document.addEventListener("keydown", function (e) {
      var k = e.key.length === 1 ? e.key.toLowerCase() : e.key;
      pos = k === code[pos] ? pos + 1 : (k === code[0] ? 1 : 0);
      if (pos === code.length) {
        pos = 0; toast("Cheat code accepted. Your spending is still real.");
        if (calm) return;
        var colours = ["#f0643d", "#f5a623", "#7b6bf0", "#2bb07a"];
        for (var i = 0; i < 90; i++) {
          var c = document.createElement("span"); c.className = "confetti";
          c.style.left = Math.random() * 100 + "vw"; c.style.background = colours[i % 4];
          c.style.animationDuration = 1.8 + Math.random() * 2 + "s"; c.style.animationDelay = Math.random() * .6 + "s";
          document.body.appendChild(c); setTimeout(function (el) { el.remove(); }, 4600, c);
        }
      }
    });

    // "Coming soon" button.
    var soon = document.querySelector(".soon-btn"), soonHits = 0;
    if (soon) {
      var soonLines = ["It's not out yet. Clicking harder won't help.", "Still not out. We checked.", "Now you're just clicking for fun. Join the beta."];
      var hitSoon = function () { toast(soonLines[Math.min(soonHits++, soonLines.length - 1)]); };
      soon.addEventListener("click", hitSoon);
      soon.addEventListener("keydown", function (e) { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); hitSoon(); } });
    }
    // Leave the tab and the title gets needy.
    var title = document.title;
    document.addEventListener("visibilitychange", function () {
      document.title = document.hidden ? "Come back, your budget misses you" : title;
    });
    // Sit still for a minute.
    var idle, idleSaid = false;
    function poke() { clearTimeout(idle); if (!idleSaid) idle = setTimeout(function () { idleSaid = true; toast("Still here? Your coffee's getting cold."); }, 60000); }
    ["mousemove", "keydown", "scroll", "touchstart"].forEach(function (ev) { window.addEventListener(ev, poke, { passive: true }); });
    poke();
    // Type "coffee".
    var typed = "";
    document.addEventListener("keydown", function (e) {
      if (e.key.length !== 1 || /input|textarea/i.test(e.target.tagName)) return;
      typed = (typed + e.key.toLowerCase()).slice(-6);
      if (typed === "coffee") toast("☕ $5.50 logged. (Not really. It's a website.)");
    });
    // Tap the receipt total.
    var total = document.querySelector(".receipt .total");
    if (total) {
      var printed = false;
      var guilt = function () {
        if (printed) { toast("One guilt line per customer."); return; }
        printed = true;
        var g = document.createElement("div"); g.className = "guilt"; g.innerHTML = "<span>Guilt</span><span>priceless</span>";
        total.insertAdjacentElement("afterend", g);
      };
      total.addEventListener("click", guilt);
      total.addEventListener("keydown", function (e) { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); guilt(); } });
    }
    // Flip the theme too many times.
    var flips = 0;
    if (btn) btn.addEventListener("click", function () {
      if (++flips === 8) toast("Light, dark, light, dark. Pick one.");
    });
    // Scroll all the way down.
    var bottomSaid = false;
    window.addEventListener("scroll", function () {
      if (!bottomSaid && window.innerHeight + window.scrollY >= document.body.scrollHeight - 4) {
        bottomSaid = true; toast("You made it to the bottom. More commitment than a gym membership.");
      }
    }, { passive: true });

    // Scroll-in for sections marked .reveal.
    var items = document.querySelectorAll(".reveal");
    if (!("IntersectionObserver" in window)) { items.forEach(function (el) { el.classList.add("in"); }); return; }
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } });
    }, { rootMargin: "0px 0px -10% 0px", threshold: 0.12 });
    items.forEach(function (el) { io.observe(el); });
  });
})();
