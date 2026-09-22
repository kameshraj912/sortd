// What the setup page tells Gmail and Outlook to forward.
//
// Keep in step with the app: every bank in Spend/Services/BankAlerts.swift
// (BankAlerts.known) and every sender in EmailParsers.ruleDomains must be here.
// SpendTests/ForwardingInboxTests.swift checks this file for each one.

/** Bank alert senders, matched on domain. */
export const BANK_DOMAINS = [
  // Australia
  "nab.com.au", "commbank.com.au", "anz.com", "westpac.com.au", "ing.com.au", "up.com.au",
  "ubank.com.au", "macquarie.com", "bendigobank.com.au", "stgeorge.com.au",
  // Singapore
  "dbs.com", "posb.com.sg", "ocbc.com", "uob.com.sg", "trustbank.sg", "gxs.com.sg",
  // Malaysia
  "maybank.com", "cimb.com",
];

/** Receipt senders the app has exact rules for. */
export const RECEIPT_DOMAINS = ["sc.com", "doordash.com", "email.apple.com", "you.co", "stripe.com", "mail.anthropic.com"];

/** Subjects that look like a purchase from anyone else. */
export const SUBJECT_WORDS = [
  "receipt", "invoice", "\"tax invoice\"", "\"order confirmation\"", "\"your order\"", "\"payment received\"",
  "\"payment confirmation\"", "\"transaction alert\"", "\"you paid\"", "refund",
];

/** Gmail search for "Has the words". Also works pasted into Gmail's search box to preview what it catches. */
export function gmailQuery() {
  const senders = [...BANK_DOMAINS, ...RECEIPT_DOMAINS].join(" OR ");
  return `from:(${senders}) OR subject:(${SUBJECT_WORDS.join(" OR ")})`;
}

/**
 * A Gmail filter file for Settings > Filters and Blocked Addresses > Import filters.
 * Same Atom format Gmail exports. Standalone (no imports) because the setup
 * page runs this exact function in the browser too.
 */
export function filterXml(address, query) {
  const attr = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/'/g, "&apos;").replace(/"/g, "&quot;");
  return [
    "<?xml version='1.0' encoding='UTF-8'?>",
    "<feed xmlns='http://www.w3.org/2005/Atom' xmlns:apps='http://schemas.google.com/apps/2006'>",
    "  <title>Mail Filters</title>",
    "  <entry>",
    "    <category term='filter'></category>",
    "    <title>Mail Filter</title>",
    "    <content></content>",
    `    <apps:property name='hasTheWord' value='${attr(query)}'/>`,
    `    <apps:property name='forwardTo' value='${attr(address)}'/>`,
    "  </entry>",
    "</feed>",
    "",
  ].join("\n");
}
