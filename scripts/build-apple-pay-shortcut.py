"""Build the ready-made Sortd Apple Pay shortcut.

The file carries two things, the way every working Wallet shortcut does
(checked against a public one that imports cleanly on iOS 27, 27 Sep 2026):

1. The triggers (`WFWorkflowTriggers`). On iOS 27 they import with the
   shortcut, switched off; the person turns each on in Automation.
   - The Wallet transaction trigger: a tap at a till. It is also what tells
     Shortcuts the input is a transaction: without it the property mappings
     below are thrown away on import and every field arrives as the whole
     input.
   - A Notification trigger for Wallet (2 Oct 2026): fires for Wallet's own
     notifications, which also cover Apple Pay in apps and on websites.
     Stored shape checked on an iOS 27 simulator on 2 Oct 2026.
2. Sortd's own action with Amount, Merchant and Card or Pass mapped straight
   from the tap (proven on Raj's phone; unchanged), plus Notification
   Title, Subtitle and Body mapped from the notification trigger's output.
   Sortd reads the notification whenever any of the three has text and
   then ignores the tap fields. "Show When Run" is off, so a run never
   stops on a dialog.

    python3 scripts/build-apple-pay-shortcut.py
    python3 scripts/build-apple-pay-shortcut.py --notification-app com.apple.MobileSMS Messages

`--notification-app` watches another app instead of Wallet, for a test build
on a simulator (`xcrun simctl push` can post a notification as that app).

There is no Text step. iOS 27 refuses to turn a Wallet transaction into text
("couldn't convert from Transaction to Text"), which stopped the shortcut
before it reached Sortd. `LogWalletTapIntent` still accepts free text for
automations people built by hand.

Transit taps are left out of the trigger: a gantry tap has no amount yet and
only produces an error.

Then sign it:
    shortcuts sign --mode anyone --input <out> --output site/apple-pay.shortcut

iOS 26 (5 Oct 2026): `--ios26` builds the second file, `site/apple-pay-26.shortcut`.
iOS 26 can't import an automation with a shortcut, so the file carries no
triggers; the person makes a Wallet automation and picks this shortcut in it.
With no trigger to say the input is a transaction, iOS 26 dropped the three
property mappings on import (every box came back as plain "Shortcut Input").
Two things keep them, checked on the iOS 26.5 simulator (Amount, Merchant and
Card or Pass all survive, and a first run with Allow reaches Sortd):
  - the shortcut accepts Wallet transactions as its input
    (`WFWalletTransactionContentItem`, a type Shortcuts' own editor never offers);
  - each variable is coerced to that type before its property is read.
Not yet proven on a real iPhone with cards: that the automation hands the
transaction to the shortcut it runs.

    python3 scripts/build-apple-pay-shortcut.py --ios26
    shortcuts sign --mode anyone --input <out> --output site/apple-pay-26.shortcut
"""

import argparse, plistlib, pathlib, pprint, uuid

OUT = pathlib.Path(__file__).resolve().parent.parent / ".build" / "shortcut" / "Log Apple Pay in Sortd.shortcut"

parser = argparse.ArgumentParser(description="Build the Sortd Apple Pay shortcut.")
parser.add_argument("--notification-app", nargs=2, metavar=("BUNDLE_ID", "NAME"),
                    default=["com.apple.Passbook", "Wallet"],
                    help="the app whose notifications the second trigger watches (default: Wallet)")
parser.add_argument("--ios26", action="store_true",
                    help="build the iOS 26 file: no triggers, input typed as a Wallet transaction")
args = parser.parse_args()
NOTIFICATION_APP, NOTIFICATION_APP_NAME = args.notification_app
IOS26 = args.ios26
if IOS26:
    OUT = OUT.parent / "ios26" / OUT.name

TRANSACTION = "WFWalletTransactionContentItem"

LOG_UUID = str(uuid.uuid4()).upper()


def token(attachment: dict) -> dict:
    """One variable, serialised the way an App Intent's text parameter wants.

    A bare WFTextTokenAttachment is silently dropped on import — checked on
    iOS 26.4: every field came back a grey placeholder. The Text action in the
    same file survived because its parameter is a WFTextTokenString holding
    the variable as an attachment at position 0. Same shape here.
    """
    return {
        "Value": {
            "string": "\ufffc",
            "attachmentsByRange": {"{0, 1}": attachment},
        },
        "WFSerializationType": "WFTextTokenString",
    }


def input_property(name: str) -> dict:
    """Shortcut Input → one property of the Wallet transaction."""
    read = [{"Type": "WFPropertyVariableAggrandizement", "PropertyName": name}]
    if IOS26:
        # No trigger says what the input is, so say it here (see the note above).
        read.insert(0, {"Type": "WFCoercionVariableAggrandizement", "CoercionItemClass": TRANSACTION})
    return token({"Type": "ExtensionInput", "Aggrandizements": read})


def notification_part(name: str) -> dict:
    """The Notification trigger's output → Title, Subtitle or Body."""
    return token({
        "Type": "TriggerOutput",
        "TriggerIdentifier": "WFNotificationTrigger",
        "Aggrandizements": [
            {"Type": "WFPropertyVariableAggrandizement", "PropertyName": name}
        ],
    })


log = {
    "WFWorkflowActionIdentifier": "com.kameshraj.sortd.LogWalletTapIntent",
    "WFWorkflowActionParameters": {
        "AppIntentDescriptor": {
            "AppIntentIdentifier": "LogWalletTapIntent",
            "BundleIdentifier": "com.kameshraj.sortd",
            "Name": "Sortd",
            "TeamIdentifier": "7CLGYQ9P3L",
        },
        "UUID": LOG_UUID,
        # "Show When Run" off. On (Shortcuts' default) every run shows Sortd's
        # dialog and waits for Done, and later runs queue behind it. Key and
        # value read from Shortcuts' own database after switching the toggle
        # off (2 Oct 2026). Sortd posts its own "Logged" notification instead.
        "ShowWhenRun": False,
        "amount": input_property("Amount"),
        "merchant": input_property("Merchant"),
        "card": input_property("Card or Pass"),
        "notificationTitle": notification_part("Title"),
        "notificationSubtitle": notification_part("Subtitle"),
        "notificationBody": notification_part("Body"),
    },
}

# The Wallet trigger. Merchant types 1-6 are every category except Transport.
wallet_trigger = {
    "WFTriggerIdentifier": "WFWalletTransactionTrigger",
    "WFTriggerUUID": str(uuid.uuid4()).upper(),
    "WFTriggerSerializedParameters": {
        "WFWalletMerchantTypes": [{"merchantType": n} for n in range(1, 7)],
    },
}

# Wallet's notifications (or the app given with --notification-app).
notification_trigger = {
    "WFTriggerIdentifier": "WFNotificationTrigger",
    "WFTriggerUUID": str(uuid.uuid4()).upper(),
    "WFTriggerSerializedParameters": {
        "SelectedApps": {
            "BundleIdentifier": NOTIFICATION_APP,
            "Name": NOTIFICATION_APP_NAME,
            "TeamIdentifier": "None",
        },
    },
}

workflow = {
    "WFWorkflowClientVersion": "4528.0.4.3",
    "WFWorkflowMinimumClientVersion": 900,
    "WFWorkflowMinimumClientVersionString": "900",
    "WFWorkflowHasOutputFallback": False,
    "WFWorkflowHasShortcutInputVariables": True,
    "WFWorkflowIcon": {
        "WFWorkflowIconStartColor": 4274264319,  # orange, like the app mark
        "WFWorkflowIconGlyphNumber": 61440,
    },
    "WFWorkflowImportQuestions": [],
    "WFWorkflowInputContentItemClasses": [
        "WFAppStoreAppContentItem",
        "WFArticleContentItem",
        "WFContactContentItem",
        "WFDateContentItem",
        "WFEmailAddressContentItem",
        "WFGenericFileContentItem",
        "WFImageContentItem",
        "WFiTunesProductContentItem",
        "WFLocationContentItem",
        "WFDCMapsLinkContentItem",
        "WFAVAssetContentItem",
        "WFPDFContentItem",
        "WFPhoneNumberContentItem",
        "WFRichTextContentItem",
        "WFSafariWebPageContentItem",
        "WFStringContentItem",
        "WFURLContentItem",
    ],
    "WFWorkflowTypes": ["WFWorkflowTypeShowInSearch"],
    "WFWorkflowOutputContentItemClasses": [],
    "WFQuickActionSurfaces": [],
    "WFWorkflowTriggers": [wallet_trigger, notification_trigger],
    "WFWorkflowActions": [log],
}

if IOS26:
    del workflow["WFWorkflowTriggers"]
    workflow["WFWorkflowInputContentItemClasses"] = [TRANSACTION]
    for part in ("notificationTitle", "notificationSubtitle", "notificationBody"):
        del log["WFWorkflowActionParameters"][part]

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(plistlib.dumps(workflow, fmt=plistlib.FMT_BINARY))
print(OUT, OUT.stat().st_size, "bytes")

# Read the file back, so what is printed is what was written.
written = plistlib.loads(OUT.read_bytes())
print("\nTriggers:")
pprint.pprint(written.get("WFWorkflowTriggers", "none (iOS 26 file)"), sort_dicts=False, width=110)
print("\nAction:")
pprint.pprint(written["WFWorkflowActions"], sort_dicts=False, width=110)
print("\nShowWhenRun:", written["WFWorkflowActions"][0]["WFWorkflowActionParameters"].get("ShowWhenRun", "missing"))
