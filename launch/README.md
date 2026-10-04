# soon.sortd.page — redirect only

This was the separate beta hype page (countdown and sign-up). On 4 Oct 2026 it was merged into
sortd.page: the full site in `../site` is the only site, and sign-ups go through sortd.page/beta.

What is left here is a tiny Worker (`redirect.js`) that sends every soon.sortd.page address to
https://sortd.page, so old links (the Instagram bio, shared posts) keep working.
The old page is in git history (last full version: commit `d4074eb`).

## Deploy (one session at a time, from a clean tree)

    cd launch && npx wrangler deploy
