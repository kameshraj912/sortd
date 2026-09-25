// soon.sortd.page: countdown, sign-up (posts to sortd.page/api/beta), share.
(function () {
  // Change the date here and nowhere else. If it passes before the beta is really
  // open, the countdown hides and the line says so instead of showing zeros.
  var BETA_OPENS = new Date("2026-10-09T09:00:00+11:00"); // 9 am Melbourne

  var box = document.querySelector("[data-count]"), note = document.querySelector("[data-count-note]");
  var pad = function (n) { return n < 10 ? "0" + n : String(n); };
  function tick() {
    var left = BETA_OPENS - Date.now();
    if (left <= 0) { box.classList.add("over"); note.textContent = "The beta opens any day now. (We said that last time too.)"; return; }
    var s = Math.floor(left / 1000);
    box.querySelector("[data-d]").textContent = Math.floor(s / 86400);
    box.querySelector("[data-h]").textContent = pad(Math.floor(s / 3600) % 24);
    box.querySelector("[data-m]").textContent = pad(Math.floor(s / 60) % 60);
    box.querySelector("[data-s]").textContent = pad(s % 60);
    box.setAttribute("aria-label", Math.floor(s / 86400) + " days until the beta opens");
  }
  if (box) { tick(); setInterval(tick, 1000); }

  // The sneak peek really does unblur on beta day.
  var peek = document.querySelector(".peek .phone");
  if (peek && Date.now() >= BETA_OPENS) { peek.classList.add("clear"); var t = peek.querySelector(".tag"); if (t) t.textContent = "Told you."; }

  var form = document.getElementById("join");
  if (form) {
    var email = form.elements.email, err = document.getElementById("error"), done = document.getElementById("done"), btn = form.querySelector("button");
    var say = function (msg) { err.textContent = msg; err.hidden = !msg; };
    var resetCaptcha = function () { try { if (window.turnstile) window.turnstile.reset(); } catch (e) {} };
    var more = document.getElementById("more"), save = form.querySelector(".save");
    var fail = function (msg, field) { say(msg); if (field) field.focus(); };
    form.addEventListener("submit", function (e) {
      e.preventDefault();
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email.value.trim())) { fail("That's not an email. Even your spam folder would reject\u00a0it.", email); return; }
      // Step 1 → step 2: open the rest of the questions in the same card.
      if (more.hidden) { say(""); more.hidden = false; btn.hidden = true; form.elements.name.focus(); return; }
      if (!form.elements.name.value.trim()) return fail("What should we call you? First name is\u00a0fine.", form.elements.name);
      if (!form.elements.country.value) return fail("Pick where you live. \"Other\"\u00a0counts.", form.elements.country);
      if (!form.querySelector('input[name="applepay"]:checked')) return fail("Pick an Apple Pay answer. \"Not sure\" is\u00a0allowed.", form.querySelector('input[name="applepay"]'));
      var g = form.elements.gmail.value.trim();
      if (g && !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(g)) return fail("That doesn't look like a Gmail\u00a0address.", form.elements.gmail);
      say(""); save.disabled = true; save.textContent = "Saving…";
      fetch(form.action, { method: "POST", body: new FormData(form), headers: { Accept: "application/json" } })
        .then(function (r) { return r.json().catch(function () { return { ok: false }; }); })
        .then(function (res) {
          if (res.ok) {
            document.getElementById("done-email").textContent = email.value.trim();
            form.hidden = true; done.hidden = false; done.querySelector("h2").focus();
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
