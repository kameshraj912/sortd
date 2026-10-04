# Beta emails

This is an expression-of-interest list. The beta isn't open yet; when it is, you send each
person the TestFlight link.

People sign up at https://sortd.page/beta. The form posts to the site's Worker
(`site/worker/index.js`), which emails each sign-up to the address in the `BETA_TO` secret,
with Reply-To set to the person. Nothing is stored anywhere else, so the emails are the list.
Label them in Gmail (subject starts "Beta sign-up:").

The form asks for:

- Email (required, where the TestFlight link goes)
- First name (optional)
- Country (optional: Australia, Singapore, Malaysia, Other)
- Apple Pay: yes / no / not sure (optional)

Cloudflare can only email verified addresses, so the form can't send people a confirmation
email. They see "You're on the list" on the page instead.

Setup (once): Email Routing on for sortd.page, the destination address verified, then
`cd site && npx wrangler secret put BETA_TO` and deploy.

## When the beta opens

1. App Store Connect → TestFlight → External testers → add their email, or create a public
   link (limit it to iOS 26 and later) and send that instead.
2. Reply with one of the emails below.
3. Log them somewhere (name, Apple ID, date) so you can clear the list when the beta ends.

On 4 Oct 2026 the external group "Beta" exists in App Store Connect with no testers, and build
1.0 (4) is with Beta App Review. Nobody can install until that passes. About 30 sign-up emails
are in Gmail (label them; several from 21 Sep look like form tests).

## Reply: you're in (friendly)

Subject: You're in the Sortd beta

> Hi [Name],
>
> Thanks for signing up. You're in.
>
> You'll get an email from Apple TestFlight in the next day or two. Tap "View in TestFlight",
> install TestFlight if you don't have it, then install Sortd.
>
> One thing while it's a beta: if something looks wrong, take a screenshot and reply to this
> email. Please hide card numbers.
>
> Thanks for helping.
>
> Raj
> Sortd

## Reply: you're in (short)

Subject: Sortd beta invite

> Hi [Name],
>
> You're in. Look out for a TestFlight email from Apple in the next day or two, then install
> Sortd from it.
>
> Reply here with any bugs.
>
> Raj

## Reply: not yet (old iOS or missing details)

Subject: Re: Join the Sortd beta

> Hi [Name],
>
> Thanks for your interest. Sortd needs iOS 26 or later, and your iPhone is on [version].
> If you can update (Settings › General › Software Update), reply and I'll send the invite.
>
> Raj
