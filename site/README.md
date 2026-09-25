# Sortd website

Seven static pages, one stylesheet and one small script. No build step, no external fonts. The only
external script is Cloudflare Turnstile on the beta form.

- `index.html` — home
- `privacy.html` — privacy policy (includes Google's Limited Use sentence)
- `support.html` — FAQ and contact
- `terms.html` — terms of use
- `beta.html`, `beta-thanks.html` — beta sign-up form and thank-you page
- `404.html` — page not found
- `site.js` — theme switch, feature tabs, beta form, scroll reveals and the easter eggs
- `style.css` — the only stylesheet (light and dark follow the device setting)

## Before publishing

Placeholders are filled (19 Sep 2026): made by Kameshraj Gnanaprakasam, contact
support@sortd.page. That address needs email forwarding set up at the domain registrar
(free at most registrars) so it reaches your inbox. Update "Last updated" when the policy changes.

If the app's behaviour changes (new data, new services it talks to), update `privacy.html` first.

## Publishing

Live at https://sortd.page (Cloudflare Workers static assets, free). Settings are in `wrangler.jsonc`;
`.assetsignore` keeps this README and the config off the site.

    cd site && npx wrangler deploy

After changing `style.css` or `site.js`, bump the `?v=` number in every page's links so browsers
fetch the new copy. Email to support@sortd.page is forwarded by Cloudflare Email Routing.

## Home page gate (until the beta opens)

`index.html` opens with the "Oops. You found us early." card (`#early`), which covers the whole home page
and links to soon.sortd.page. `site.js` adds the `gate` class on `/` only; other pages are not gated.
Keep the card's one-line description and the privacy link: Google's Gmail verification checks the home page.
To lift the gate: delete the `<dialog id="early">` block and the gate lines in `site.js`.
