# Sortd website

Four static pages and one stylesheet. No build step, no external scripts or fonts.

- `index.html` — home
- `privacy.html` — privacy policy (includes Google's Limited Use sentence)
- `support.html` — FAQ and contact
- `terms.html` — terms of use
- `style.css` — the only stylesheet (light and dark follow the device setting)

## Before publishing

Replace every placeholder in all four pages:

- `[CONTACT EMAIL]`
- `[DATE]` (privacy.html and terms.html)
- `[DEVELOPER / COMPANY NAME]`

Check nothing is left: `grep -n "\[" site/*.html`

If the app's behaviour changes (new data, new services it talks to), update `privacy.html` first.

## Publish free with GitHub Pages

GitHub Pages can only serve from the repo root or a `/docs` folder, not `/site`. The simplest
free way to publish just this folder is a GitHub Actions workflow:

1. Push the repo to GitHub. On a free account the repo must be **public** for Pages to work
   (Pages on private repos needs a paid plan). If you don't want the app code public, make a
   separate public repo that contains only these files, and put them at its root — then in
   step 2 choose **Deploy from a branch**, branch `main`, folder `/ (root)`, and skip step 3.
2. In the repo on GitHub: **Settings › Pages › Build and deployment › Source: GitHub Actions**.
3. Add `.github/workflows/pages.yml`:

   ```yaml
   name: Publish site
   on:
     push:
       branches: [main]
       paths: [site/**]
     workflow_dispatch:
   permissions:
     contents: read
     pages: write
     id-token: write
   jobs:
     deploy:
       runs-on: ubuntu-latest
       environment:
         name: github-pages
         url: ${{ steps.deployment.outputs.page_url }}
       steps:
         - uses: actions/checkout@v4
         - uses: actions/upload-pages-artifact@v3
           with:
             path: site
         - id: deployment
           uses: actions/deploy-pages@v4
   ```

4. Push to `main`. The site appears at `https://<your-github-username>.github.io/<repo-name>/`.

### Own domain (needed for Google verification)

Google's OAuth verification needs a domain you own and have verified in Google Search Console.
A `github.io` address is owned by GitHub, so it won't pass. To use your own domain
(for example `sortdmoney.com`, which was free on 19 Sep 2026 — not bought yet):

1. Buy the domain.
2. **Settings › Pages › Custom domain**: enter it and save. Tick **Enforce HTTPS** once it's offered.
3. At your domain registrar, add the DNS records GitHub shows (for a bare domain: four `A`
   records to GitHub's IPs; for `www`: a `CNAME` to `<your-github-username>.github.io`).
4. Verify the domain in Google Search Console with the same Google account that owns the
   Sortd Google Cloud project.

Check these steps against GitHub's and Google's current docs when you do them.

## Which URL goes where

Below, `https://<site>` means your final address (your own domain, or the github.io one).

### App Store Connect

| Field | URL |
|---|---|
| App Privacy › Privacy Policy URL | `https://<site>/privacy.html` |
| App Information › Support URL | `https://<site>/support.html` |
| App Information › Marketing URL (optional) | `https://<site>/` |
| Terms of Use / EULA | Leave on Apple's standard EULA, or add `https://<site>/terms.html` as a custom one. Needed in the listing once you sell subscriptions. |

### Google Cloud › OAuth consent screen (Branding)

| Field | URL |
|---|---|
| Application home page | `https://<site>/` |
| Application privacy policy link | `https://<site>/privacy.html` |
| Application terms of service link | `https://<site>/terms.html` |
| Authorised domains | your domain only, e.g. `sortdmoney.com` (no `https://`, no path) |

The home page must describe the app and link to the privacy policy, and the privacy policy
must be on the same verified domain. Both are already true of these pages.
