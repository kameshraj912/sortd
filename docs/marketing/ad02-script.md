# Ad 02: Sortd beta Reel (32 s, 9:16). Replaces Ad 01.

- **Why the redo:** Ad 01 had too many AI people and places, and the cuts felt random.
- **The fix:** keep only the two AI clips that read as real, as bookends. The middle is dbrand-style roast text over real Sortd footage.
- **Timing:** every cut lands on the beat of "Melbourne Housemates" (76 bpm, one beat = 0.79 s).
- **Build:** `claude-project/ads/ad02/src/build.py`
- **Output:** `~/Downloads/sortd-beta-reel/`

| Time | Beats | Picture | On screen / heard |
|---|---|---|---|
| 0.0 | 4 | Kitchen: Nik eating noodles (Veo) | "Where'd your money go last month?" / "Groceries." |
| 3.2 | 2 | Card | **Wrong.** Music cuts dead |
| 4.7 | 2 | Card | It was takeaway. / It's *always* takeaway. |
| 6.3 | 2 | Card with app icon | **Meet Sortd.** / It remembers what you'd rather forget. |
| 7.9 | 4 | Real app: banner "Logged $5.50 at Seven Seeds Coffee", row slides in | Tap to pay. → Sortd writes it down. Payment beep |
| 11.1 | 4 | Real app: Home, card carousel (SGD, AUD cards), scroll | Every card. Every currency. → Every "just one coffee." |
| 14.2 | 4 | Card | No bank login. / No account. / Your data stays on your phone. |
| 17.4 | 2 | Card | We can't sell it. / We don't *have it.* |
| 18.9 | 3 | Card | Now in **beta.** / Bugs included. Free of charge. |
| 21.3 | 10 | Couch: all three (Veo). Music out | "This was an ad. For Sortd." / "We're not even real." / "The takeaway was…" *(bite)* |
| 29.2 | 4 | End card | sortd · Unlike the takeaway, it's free. · **Free beta. Link in bio.** · sortd.page |

## Where the footage comes from

**Real app shots**
- Simulator on the iPhone Pro Max, running the demo data.
- The tap runs through `LogPurchaseIntent` using the DEBUG switch `SPEND_REEL_TAP` in `SpendApp.swift`.

**Checked before sending**
- Frame sheet at 2 frames per second.
- Whisper transcript: every line complete.
- Silence on "Wrong." measured at −91 dB.
- Speech at about −17 dB, music under the cards at about −23 dB.
- Output is 48 kHz, 30 fps.

## Posting
- **Caption:** "Tap to pay. Sortd writes it down. Free beta, link in bio."
- Expect Instagram's "AI info" label. The closer jokes about it.
