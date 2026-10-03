// soon.sortd.page: countdown, sign-up (posts to sortd.page/api/beta), share.
(function () {
  document.documentElement.classList.add("js");
  var calm = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Odometer digits: each digit is a strip [max, 0..max]; digit d sits at row d+1.
  // Counting down past 0 rolls to the top copy of max, then jumps to the real one.
  function odo(b, maxes) {
    b.textContent = "";
    var cols = maxes.map(function (max) {
      var col = document.createElement("span"), strip = document.createElement("span");
      col.className = "col"; strip.className = "strip"; col.setAttribute("aria-hidden", "true");
      var rows = [max]; for (var i = 0; i <= max; i++) rows.push(i);
      strip.innerHTML = rows.map(function (n) { return "<span>" + n + "</span>"; }).join("");
      col.appendChild(strip); b.appendChild(col);
      return { strip: strip, max: max, d: 0 };
    });
    function go(c, row, instant) {
      c.strip.classList.toggle("jump", !!instant);
      c.strip.style.transform = "translateY(" + (-row) + "em)";
    }
    cols.forEach(function (c) { go(c, 1, true); });
    return function (value, spin) {
      var s = String(value); while (s.length < cols.length) s = "0" + s;
      cols.forEach(function (c, i) {
        var d = Math.min(+s[s.length - cols.length + i], c.max);
        if (d === c.d && !spin) return;
        c.strip.classList.toggle("spin", !!spin);
        if (!calm && !spin && d === c.max && c.d === 0) {
          go(c, 0); // roll up to the top copy, then swap to the real one unseen
          setTimeout(function () { go(c, c.max + 1, true); }, 520);
        } else go(c, d + 1, calm);
        c.d = d;
      });
    };
  }
  // Change the date here and nowhere else. If it passes before the beta is really
  // open, the countdown hides and the line says so instead of showing zeros.
  var BETA_OPENS = new Date("2026-10-09T09:00:00+11:00"); // 9 am Melbourne

  var box = document.querySelector("[data-count]"), note = document.querySelector("[data-count-note]");
  var setD, setH, setM, setS, first = true;
  if (box) {
    setD = odo(box.querySelector("[data-d]"), [9, 9]); setH = odo(box.querySelector("[data-h]"), [2, 9]);
    setM = odo(box.querySelector("[data-m]"), [5, 9]); setS = odo(box.querySelector("[data-s]"), [5, 9]);
  }
  function tick() {
    var left = BETA_OPENS - Date.now();
    if (left <= 0) { box.classList.add("over"); note.textContent = "The beta opens any day now. (We said that last time too.)"; return; }
    var s = Math.floor(left / 1000);
    var spin = first && !calm; first = false;
    setD(Math.min(Math.floor(s / 86400), 99), spin); setH(Math.floor(s / 3600) % 24, spin);
    setM(Math.floor(s / 60) % 60, spin); setS(s % 60, spin);
    box.setAttribute("aria-label", Math.floor(s / 86400) + " days until the beta opens");
  }
  // The first values spin in once the boxes have landed.
  if (box) setTimeout(function () { tick(); setInterval(tick, 1000); }, calm ? 0 : 1250);

  // Scroll reveals, and the sneak-peek phone tilting up to face you.
  var seen = document.querySelectorAll(".reveal, .reveal-group, .peek");
  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } });
    }, { rootMargin: "0px 0px -12% 0px" });
    seen.forEach(function (el) { io.observe(el); });
  } else seen.forEach(function (el) { el.classList.add("in"); });
  var phone = document.querySelector(".peek .phone");
  if (phone && !calm) {
    var ticking = false;
    var tilt = function () {
      ticking = false;
      var r = phone.getBoundingClientRect(), vh = window.innerHeight;
      var p = Math.min(Math.max((vh - r.top) / (vh * 0.85), 0), 1); // 0 entering, 1 settled
      var e = 1 - Math.pow(1 - p, 3);
      phone.style.setProperty("--tilt", (38 * (1 - e)).toFixed(2) + "deg");
      phone.style.setProperty("--zoom", (0.86 + 0.14 * e).toFixed(3));
    };
    addEventListener("scroll", function () { if (!ticking) { ticking = true; requestAnimationFrame(tilt); } }, { passive: true });
    tilt();
  }

  // Done: the app's whole trick in two seconds. A card taps, and the purchase
  // writes itself into today's list. No typing. Then the line lands.
  var SPRING = getComputedStyle(document.documentElement).getPropertyValue("--spring").trim() || "ease-out";
  var OUT = "cubic-bezier(.16,1,.3,1)";
  var wait = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };
  function tapLog(done) {
    var card = done.querySelector(".paycard"), tick = done.querySelector(".pc-tick"), waves = done.querySelectorAll(".pc-wave"),
        log = done.querySelector(".log"), slot = done.querySelector(".log-new"), row = slot.querySelector(".row"),
        name = row.querySelector("b"), title = done.querySelector(".title"), rest = done.querySelectorAll(":scope > p, :scope > .share");
    if (!card.animate) return;
    done.classList.add("playing");
    var word = name.dataset.type; name.textContent = "";
    slot.style.height = "0px";
    log.animate([{ opacity: 0, transform: "translateY(24px)" }, { opacity: 1, transform: "none" }], { duration: 600, easing: OUT });
    card.animate([{ opacity: 0, transform: "translate(120px, -30px) rotate(14deg)" }, { opacity: 1, transform: "rotate(-4deg)" }], { duration: 700, easing: SPRING });
    return wait(750).then(function () {
      // The tap: card dips toward the reader and springs back.
      card.animate([{ transform: "rotate(-4deg)" }, { transform: "translateY(10px) rotate(-1deg) scale(.95)", offset: .35 }, { transform: "rotate(-4deg)" }],
        { duration: 520, easing: SPRING });
      return wait(180);
    }).then(function () {
      waves.forEach(function (w, k) {
        w.animate([{ opacity: .9, transform: "scale(1)" }, { opacity: 0, transform: "scale(1.35, 1.6)" }], { duration: 800, delay: k * 140, easing: "cubic-bezier(.2,.6,.3,1)" });
      });
      tick.animate([{ opacity: 0, transform: "scale(.3)" }, { opacity: 1, transform: "scale(1)" }], { duration: 500, easing: SPRING, fill: "forwards" });
      tick.querySelector("path").animate([{ strokeDashoffset: 24 }, { strokeDashoffset: 0 }], { duration: 360, delay: 120, easing: "ease-out", fill: "backwards" });
      if (navigator.vibrate) navigator.vibrate(10);
      return wait(320);
    }).then(function () {
      // The row opens at the top of today's list, pushing the coffees down.
      var h = row.offsetHeight + "px";
      slot.animate([{ height: "0px" }, { height: h }], { duration: 520, easing: OUT });
      slot.style.height = "";
      row.animate([{ opacity: 0, transform: "translateY(-18px) scale(.96)" }, { opacity: 1, transform: "none" }], { duration: 650, easing: SPRING });
      row.animate([{ backgroundColor: "rgba(43,176,122,.22)" }, { backgroundColor: "rgba(43,176,122,0)" }], { duration: 1600, delay: 300, easing: "ease-out" });
      return wait(260);
    }).then(function () {
      // Sortd writes it down.
      name.classList.add("typing");
      var i = 0;
      return new Promise(function (r) {
        var step = function () { name.textContent = word.slice(0, ++i); if (i < word.length) setTimeout(step, 45); else r(); };
        step();
      });
    }).then(function () { return wait(380); }).then(function () {
      name.classList.remove("typing");
      done.classList.remove("playing");
      title.animate([{ opacity: 0, transform: "translateY(20px) scale(.96)", filter: "blur(8px)" }, { opacity: 1, transform: "none", filter: "blur(0)" }], { duration: 800, easing: OUT });
      rest.forEach(function (el, k) {
        el.animate([{ opacity: 0, transform: "translateY(16px)" }, { opacity: 1, transform: "none" }], { duration: 700, delay: 140 + k * 110, easing: OUT, fill: "backwards" });
      });
    });
  }

  // Sneak peek: a small loupe clears one circle of the blurred screen. It follows a finger
  // or the pointer; left alone, it drifts around by itself once the phone is on screen.
  var lensPhone = document.querySelector(".peek .phone");
  if (lensPhone && !lensPhone.classList.contains("clear")) {
    var lens = lensPhone.querySelector(".lens"), held = false, lastTouch = 0, t0 = performance.now(), live = false;
    var place = function (x, y) {
      var w = lens.clientWidth, h = lens.clientHeight;
      lensPhone.style.setProperty("--lx", Math.max(30, Math.min(w - 30, x)).toFixed(1) + "px");
      lensPhone.style.setProperty("--ly", Math.max(30, Math.min(h - 30, y)).toFixed(1) + "px");
    };
    var fromEvent = function (e) {
      var r = lens.getBoundingClientRect();
      place((e.clientX - r.left) * lens.clientWidth / r.width, (e.clientY - r.top) * lens.clientHeight / r.height);
    };
    lensPhone.addEventListener("pointerdown", function (e) { held = true; lastTouch = performance.now(); fromEvent(e); });
    lensPhone.addEventListener("pointermove", function (e) { if (e.pointerType === "mouse" || held) { lastTouch = performance.now(); fromEvent(e); } });
    addEventListener("pointerup", function () { held = false; });
    var drift = function (now) {
      if (live && now - lastTouch > 2500 && !calm) {
        var t = (now - t0) / 1000, w = lens.clientWidth, h = lens.clientHeight;
        place(w * (.5 + .28 * Math.sin(t * .7)), h * (.45 + .3 * Math.sin(t * .43 + 1)));
      }
      requestAnimationFrame(drift);
    };
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (es) { live = es[0].isIntersecting; lensPhone.classList.toggle("looking", live); }, { threshold: .4 }).observe(lensPhone);
    } else { live = true; lensPhone.classList.add("looking"); }
    requestAnimationFrame(drift);
  }

  // A wrong answer shakes the field it's about.
  var shake = function (el) { if (!el || calm) return; el.classList.remove("shake"); void el.offsetWidth; el.classList.add("shake"); };

  // The sneak peek really does unblur on beta day.
  var peek = document.querySelector(".peek .phone");
  if (peek && Date.now() >= BETA_OPENS) { peek.classList.add("clear"); var t = peek.querySelector(".tag"); if (t) t.textContent = "Told you."; }

  var form = document.getElementById("join");
  if (form) {
    var email = form.elements.email, err = document.getElementById("error"), done = document.getElementById("done"), btn = form.querySelector("button");
    var say = function (msg) { err.textContent = msg; err.hidden = !msg; };
    var resetCaptcha = function () { try { if (window.turnstile) window.turnstile.reset(); } catch (e) {} };
    var more = document.getElementById("more"), save = form.querySelector(".save");
    var fail = function (msg, field) {
      say(msg); if (!field) return;
      field.focus(); shake(field.closest(".row, .f") || field);
    };
    form.addEventListener("submit", function (e) {
      e.preventDefault();
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email.value.trim())) { fail("That's not an email. Even your spam folder would reject\u00a0it.", email); return; }
      // Step 1 → step 2: open the rest of the questions in the same card.
      if (more.hidden) { say(""); more.hidden = false; btn.hidden = true; form.elements.name.focus(); return; }
      if (!form.elements.name.value.trim()) return fail("What should we call you? First name is\u00a0fine.", form.elements.name);
      if (!form.elements.country.value) return fail("Pick where you live. \"Other\"\u00a0counts.", form.elements.country);
      if (!form.querySelector('input[name="applepay"]:checked')) return fail("Pick an Apple Pay answer. \"Not sure\" is\u00a0allowed.", form.querySelector('input[name="applepay"]'));
      say(""); save.disabled = true; save.textContent = "Saving…";
      fetch(form.action, { method: "POST", body: new FormData(form), headers: { Accept: "application/json" } })
        .then(function (r) { return r.json().catch(function () { return { ok: false }; }); })
        .then(function (res) {
          if (res.ok) {
            document.getElementById("done-email").textContent = email.value.trim();
            var show = function () { form.hidden = true; done.hidden = false; done.querySelector("h2").focus({ preventScroll: true }); if (!calm) tapLog(done); };
            if (calm) show(); else { form.classList.add("leaving"); setTimeout(show, 280); }
          } else { say(res.error || "That didn't go through. Please try again."); resetCaptcha(); }
        })
        .catch(function () { say("You seem to be offline. Try again when the Wi-Fi comes back."); resetCaptcha(); })
        .then(function () { save.disabled = false; save.textContent = "Save my spot"; });
    });
  }

  var share = document.querySelector("[data-share]");
  if (share) share.addEventListener("click", function () {
    var data = { title: "Sortd", text: "An app that logs your Apple Pay taps by itself. Free beta soon:", url: "https://soon.sortd.page" };
    if (navigator.share) { navigator.share(data).catch(function () {}); return; }
    try { navigator.clipboard.writeText(data.url); share.textContent = "Link copied"; } catch (e) {}
  });
})();
