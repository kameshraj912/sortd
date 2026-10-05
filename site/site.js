// Sortd website: light/dark switch and gentle scroll-in. Loaded in <head> so the
// chosen theme is applied before the page paints (no flash).
(function () {
  try { console.log("%csortd", "font:800 28px -apple-system,sans-serif;letter-spacing:-1px", "\nReading the source? Respect.\nNo trackers in here, promise. Check the Network tab.\nWe're not hiring yet, but say hi: support@sortd.page"); } catch (e) {}
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
    // Beta sign-up: send without leaving the page, then open TestFlight (the Worker hands back the link).
    var form = document.getElementById("beta-form");
    if (form) {
      var err = document.getElementById("beta-error"), done = document.getElementById("beta-done");
      var email = form.elements.email, submit = form.querySelector('button[type="submit"]');
      var ok = function (v) { return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(v); };
      var show = function (msg, field) {
        err.textContent = msg; err.hidden = !msg;
        [email, form.elements.name, form.elements.country, form.elements.iphone].forEach(function (f) { if (f) f.removeAttribute("aria-invalid"); });
        if (field) { field.setAttribute("aria-invalid", "true"); field.focus(); }
      };
      // Turnstile tokens are single-use: after a failed submit, clear it so the next try gets a fresh one.
      var resetCaptcha = function () { try { if (window.turnstile) window.turnstile.reset(); } catch (e) {} };
      // Screen size in points and pixel ratio, e.g. "393x852@3". Sent with the form, and used for the guess below.
      var screenSize = function () {
        try { return Math.min(screen.width, screen.height) + "x" + Math.max(screen.width, screen.height) + "@" + (window.devicePixelRatio || 1); } catch (e) { return ""; }
      };
      // "Which iPhone?": the browser never says the model, so the iPhones that share this screen
      // size go to the top of the list. Instagram's and Facebook's in-app browsers do name the
      // exact model; only then is it picked for them, so nobody is left on a wrong guess.
      // Keep the two tables in step with SCREENS and IPHONES in worker/index.js.
      var pick = form.elements.iphone;
      if (pick && /iPhone/.test(navigator.userAgent)) {
        var GROUPS = {
          "375x667@2": ["iPhone SE (3rd generation)", "iPhone SE (2nd generation)"],
          "414x896@2": ["iPhone 11"],
          "375x812@3": ["iPhone 13 mini", "iPhone 12 mini", "iPhone 11 Pro"],
          "414x896@3": ["iPhone 11 Pro Max"],
          "390x844@3": ["iPhone 17e", "iPhone 16e", "iPhone 14", "iPhone 13 Pro", "iPhone 13", "iPhone 12 Pro", "iPhone 12"],
          "428x926@3": ["iPhone 14 Plus", "iPhone 13 Pro Max", "iPhone 12 Pro Max"],
          "393x852@3": ["iPhone 16", "iPhone 15 Pro", "iPhone 15", "iPhone 14 Pro"],
          "430x932@3": ["iPhone 16 Plus", "iPhone 15 Pro Max", "iPhone 15 Plus", "iPhone 14 Pro Max"],
          "402x874@3": ["iPhone 18 Pro", "iPhone 17 Pro", "iPhone 17", "iPhone 16 Pro"],
          "440x956@3": ["iPhone 18 Pro Max", "iPhone 17 Pro Max", "iPhone 16 Pro Max"],
          "420x912@3": ["iPhone Air"]
        };
        var CODES = {
          "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max", "iPhone12,8": "iPhone SE (2nd generation)",
          "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
          "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13", "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
          "iPhone14,6": "iPhone SE (3rd generation)", "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
          "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max", "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
          "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
          "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max", "iPhone17,5": "iPhone 16e",
          "iPhone18,3": "iPhone 17", "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max", "iPhone18,4": "iPhone Air"
        };
        var code = navigator.userAgent.match(/Instagram [\d.]+ \((\w+,\d+);/) || navigator.userAgent.match(/FBDV\/(\w+,\d+)/);
        var exact = (code && CODES[code[1]]) || "";
        var likely = exact ? [exact] : (GROUPS[screenSize()] || []);
        if (likely.length) {
          var first = document.createElement("optgroup"), rest = document.createElement("optgroup");
          first.label = exact ? "Your iPhone" : "Looks like yours"; rest.label = "All iPhones";
          [].slice.call(pick.options).forEach(function (o) { if (o.value) (likely.indexOf(o.value) >= 0 ? first : rest).appendChild(o); });
          pick.appendChild(first); pick.appendChild(rest);
          if (exact) { pick.value = exact; document.getElementById("f-iphone-hint").textContent = "We filled this in from your phone. Change it if it's\u00a0wrong."; }
        }
      }
      if (/[?&]error=1/.test(location.search)) show("That didn't go through. Please try\u00a0again.");
      form.addEventListener("submit", function (e) {
        e.preventDefault();
        if (!ok(email.value.trim())) return show("That's not an email. Even your spam folder would reject\u00a0it.", email);
        // The home page waitlist only asks for an email; the /beta form asks the rest.
        if (form.elements.name && !form.elements.name.value.trim()) return show("What should we call you? First name is\u00a0fine.", form.elements.name);
        if (form.elements.country && !form.elements.country.value) return show("Pick where you live. \"Other\"\u00a0counts.", form.elements.country);
        if (form.elements.iphone && !form.elements.iphone.value) return show("Pick your iPhone. \"Not sure\"\u00a0counts.", form.elements.iphone);
        if (form.querySelector('input[name="applepay"]') && !form.querySelector('input[name="applepay"]:checked')) return show("Pick an Apple Pay answer. \"Not sure\" is\u00a0allowed.", form.querySelector('input[name="applepay"]'));
        show(""); submit.disabled = true; submit.textContent = "Sending…";
        var data = new FormData(form);
        if (screenSize()) data.append("screen", screenSize());
        fetch(form.action, { method: "POST", body: data, headers: { Accept: "application/json" } })
          .then(function (r) { return r.json().catch(function () { return { ok: false }; }); })
          .then(function (res) {
            if (res.ok) {
              ["beta-intro", "beta-alt"].forEach(function (id) { var n = document.getElementById(id); if (n) n.hidden = true; });
              document.getElementById("beta-done-email").textContent = email.value.trim();
              form.hidden = true; done.hidden = false;
              if (!form.hasAttribute("data-stay")) window.scrollTo(0, 0);
              var h = done.querySelector(".as-h1"); h.setAttribute("tabindex", "-1"); h.focus();
              var next = document.getElementById("beta-next");
              if (next && res.next) { next.href = res.next; setTimeout(function () { location.href = res.next; }, 1500); }
              else if (next) next.hidden = true;
            }
            else { show(res.error || "That didn't go through. Please try\u00a0again."); resetCaptcha(); }
          })
          .catch(function () { show("You seem to be offline. Try again when the Wi-Fi comes\u00a0back."); resetCaptcha(); })
          .then(function () { submit.disabled = false; submit.textContent = "Join the beta"; });
      });
    }

    // Motion helpers: split a heading into words (and the hero into its two lines),
    // number the bank chips, and give $0 an asterisk that falls off.
    var calm = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (!calm) {
      var h1 = document.querySelector(".hero h1");
      if (h1 && h1.querySelector("br")) {
        var parts = h1.innerHTML.split(/<br\s*\/?>/i);
        h1.innerHTML = parts.map(function (t) { return '<span class="m-line">' + t + "</span>"; }).join("<br>");
      }
      document.querySelectorAll(".bg-chips").forEach(function (g) { Array.prototype.forEach.call(g.children, function (c, k) { c.style.setProperty("--k", k); }); });
      var price = document.querySelector(".plans .price");
      if (price) { var ast = document.createElement("span"); ast.className = "m-ast"; ast.setAttribute("aria-hidden", "true"); ast.textContent = "*"; price.appendChild(ast); }
    }

    // Share after signing up: the phone's share sheet, or copy the link.
    document.querySelectorAll("[data-share]").forEach(function (b) {
      b.addEventListener("click", function () {
        var data = { title: "Sortd", text: "Found an app that logs your Apple Pay taps by itself. The free beta is open:", url: "https://sortd.page" };
        if (navigator.share) { navigator.share(data).catch(function () {}); return; }
        try { navigator.clipboard.writeText(data.url); b.textContent = "Link copied"; } catch (e) {}
      });
    });

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
      document.body.appendChild(t); requestAnimationFrame(function () { t.classList.add("is-on"); });
      setTimeout(function () { t.classList.remove("is-on"); setTimeout(function () { t.remove(); }, 500); }, 3200);
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
      if (taps >= 5) { e.preventDefault(); taps = 0; toast("Five taps. More than you've checked your budget this\u00a0month."); }
      else if (taps > 1) e.preventDefault();
    });
    // ↑ ↑ ↓ ↓ ← → ← → B A
    var code = ["ArrowUp","ArrowUp","ArrowDown","ArrowDown","ArrowLeft","ArrowRight","ArrowLeft","ArrowRight","b","a"], pos = 0;
    document.addEventListener("keydown", function (e) {
      var k = e.key.length === 1 ? e.key.toLowerCase() : e.key;
      pos = k === code[pos] ? pos + 1 : (k === code[0] ? 1 : 0);
      if (pos === code.length) {
        pos = 0; toast("Cheat code accepted. Your spending is still\u00a0real.");
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
      var soonLines = ["It's not out yet. Clicking harder won't\u00a0help.", "Still not out. We\u00a0checked.", "Now you're just clicking for fun. Join the\u00a0beta."];
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
    function poke() { clearTimeout(idle); if (!idleSaid) idle = setTimeout(function () { idleSaid = true; toast("Still here? Your coffee's getting\u00a0cold."); }, 60000); }
    ["mousemove", "keydown", "scroll", "touchstart"].forEach(function (ev) { window.addEventListener(ev, poke, { passive: true }); });
    poke();
    // Type "coffee".
    var typed = "";
    document.addEventListener("keydown", function (e) {
      if (e.key.length !== 1 || /input|textarea/i.test(e.target.tagName)) return;
      typed = (typed + e.key.toLowerCase()).slice(-6);
      if (typed === "coffee") toast("☕ $5.50 logged. (Not\u00a0really. It's a\u00a0website.)");
    });
    // Tap the receipt total.
    var total = document.querySelector(".receipt .total");
    if (total) {
      var printed = false;
      var guilt = function () {
        if (printed) { toast("One guilt line per\u00a0customer."); return; }
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
      if (++flips === 8) toast("Light, dark, light, dark. Pick\u00a0one.");
    });
    // Scroll all the way down.
    var bottomSaid = false;
    window.addEventListener("scroll", function () {
      if (!bottomSaid && window.innerHeight + window.scrollY >= document.body.scrollHeight - 4) {
        bottomSaid = true; toast("You made it to the bottom. More commitment than a\u00a0gym\u00a0membership.");
      }
    }, { passive: true });

    // Scroll-in for sections marked .reveal.
    //
    // These start at opacity 0, so a missed reveal isn't a missing
    // animation — it's missing content. Two things guard against that.
    //
    // threshold 0 rather than 0.12: a section taller than the phone, or one
    // you flick past quickly, can struggle to get 12% of itself inside the
    // root. Any pixel is enough.
    //
    // And a sweep, in case the observer is never called at all: anything
    // that has reached the bottom of the screen gets shown regardless.
    var items = document.querySelectorAll(".reveal");
    if (!("IntersectionObserver" in window)) { items.forEach(function (el) { el.classList.add("in"); }); return; }

    function reveal(el) { el.classList.add("in"); }

    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { if (e.isIntersecting) { reveal(e.target); io.unobserve(e.target); } });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0 });
    items.forEach(function (el) { io.observe(el); });

    var sweeping = false;
    function sweep() {
      sweeping = false;
      var limit = window.innerHeight;
      var left = 0;
      items.forEach(function (el) {
        if (el.classList.contains("in")) return;
        if (el.getBoundingClientRect().top < limit) { reveal(el); io.unobserve(el); } else { left++; }
      });
      if (!left) { window.removeEventListener("scroll", onScroll); }
    }
    function onScroll() {
      if (sweeping) return;
      sweeping = true;
      requestAnimationFrame(sweep);
    }
    window.addEventListener("scroll", onScroll, { passive: true });
    sweep();
  });
})();
