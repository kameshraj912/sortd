// sortd-inbox: the receipt-forwarding inbox. See docs/ForwardingInbox.md.
//
//   email()  mail to <random>@in.sortd.page  -> encrypted, kept 24 h for the phone
//   fetch()  https://inbox.sortd.page/api/inbox/...  -> the app's API
//            https://inbox.sortd.page/setup          -> "set up on your computer" page
//
// This Worker never holds a private key, never stores readable mail, and never
// logs addresses, senders, subjects or bodies.

import { handleApi } from "./api.js";
import { handleEmail } from "./email.js";
import { serveSetup } from "./setup.js";
import { json } from "./util.js";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (url.pathname.startsWith("/api/inbox")) return await handleApi(request, env, Date.now());
      const page = serveSetup(url.pathname, env.INBOX_DOMAIN);
      if (page) return page;
      if (url.pathname === "/") return Response.redirect(new URL("/setup", url), 302);
      return json({ ok: false, error: "Not found." }, 404);
    } catch (e) {
      // The error's name only: a message could quote request data.
      console.log(JSON.stringify({ event: "error", where: "fetch", name: e && e.name }));
      return json({ ok: false, error: "Something went wrong." }, 500);
    }
  },

  async email(message, env) {
    try {
      await handleEmail(message, env);
    } catch (e) {
      console.log(JSON.stringify({ event: "error", where: "email", name: e && e.name }));
      // Refuse rather than drop silently: the sender (Gmail, for a forward) tells the user it bounced.
      message.setReject("Sortd couldn't take this message right now");
    }
  },
};
