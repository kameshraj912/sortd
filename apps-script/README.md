# Spend — Gmail sync setup

Do this once in **each** Gmail account you want to read. About 5 minutes each.

The script only **reads** Gmail. It never sends, moves, labels or deletes mail.

## 1. Create the script

1. Sign in to the Gmail account in Chrome, then open <https://script.google.com> → **New project**.
2. Rename it **Spend Sync** (top left).
3. Delete the sample code in `Code.gs` and paste the whole of `Code.js` from this folder.
4. Click **+** next to Files → **Script** → name it `Parsers`. Paste the whole of `Parsers.js`.
5. In `Code.gs`, fill in `CARD_MAP` with your cards' last 4 digits, for example:

   ```js
   var CARD_MAP = {
     '1234': 'nab',        // NAB Debit
     '2345': 'scDebit',    // StanChart Debit
     '3456': 'stanchart',  // StanChart Credit
     '4567': 'cimb',       // CIMB
     '5678': 'youtrip',    // YouTrip
   };
   ```

   Valid ids: `nab`, `scDebit`, `stanchart`, `youtrip`, `maybank`, `cimb`.
6. Press **Save** (⌘S).

## 2. Run setup

1. In the function menu at the top, pick **setup**, then **Run**.
2. Google asks for permission. Choose your account → **Advanced** → **Go to Spend Sync (unsafe)** → **Allow**.
   It says "unsafe" only because you wrote the script yourself and Google hasn't reviewed it.
   It asks for: read Gmail, create one Google Sheet, run on a timer.
3. Open **Execution log**. Copy the **secret key** printed at the end.

## 3. Publish the web link

1. **Deploy** → **New deployment** → gear icon → **Web app**.
2. Execute as: **Me**. Who has access: **Anyone**.
   (The link only returns data when the secret key is sent with it.)
3. **Deploy** → copy the **Web app URL** (ends in `/exec`).

## 4. Add it to Spend

On the iPhone: **Settings → Email Receipts → Add Gmail Account**.
Paste the URL and the key, give it a name, **Save**. Spend checks the link works and runs a first sync.

## What it reads

| Sender | Becomes |
|---|---|
| Standard Chartered alerts (`alerts.sg@sc.com`) | purchases and reversals |
| DoorDash order confirmations | purchases (restaurant name, total charged) |
| Apple tax invoices / receipts | App Store purchases and subscriptions |
| YouTrip daily summaries | purchases |
| Stripe receipts and refunds, Anthropic invoices | purchases and refunds |

Everything is kept in a private Google Sheet called **Spend – email purchases (private)** in that account's Drive, so you can see exactly what was read.

## Updating

When `Parsers.js` changes, paste the new version in, save, then **Deploy → Manage deployments → Edit → Version: New version → Deploy**. The URL stays the same.

## Tests

```bash
node --test apps-script/test
```
