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
   then ignores the tap fields.

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
"""

import argparse, plistlib, pathlib, pprint, uuid

OUT = pathlib.Path(__file__).resolve().parent.parent / ".build" / "shortcut" / "Log Apple Pay in Sortd.shortcut"

parser = argparse.ArgumentParser(description="Build the Sortd Apple Pay shortcut.")
parser.add_argument("--notification-app", nargs=2, metavar=("BUNDLE_ID", "NAME"),
                    default=["com.apple.Passbook", "Wallet"],
                    help="the app whose notifications the second trigger watches (default: Wallet)")
args = parser.parse_args()
NOTIFICATION_APP, NOTIFICATION_APP_NAME = args.notification_app

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
    return token({
        "Type": "ExtensionInput",
        "Aggrandizements": [
            {"Type": "WFPropertyVariableAggrandizement", "PropertyName": name}
        ],
    })


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
    "WFWorkflowActionIdentifier": "com.kameshraj.spend.LogWalletTapIntent",
    "WFWorkflowActionParameters": {
        "AppIntentDescriptor": {
            "AppIntentIdentifier": "LogWalletTapIntent",
            "BundleIdentifier": "com.kameshraj.spend",
            "Name": "Sortd",
            "TeamIdentifier": "7CLGYQ9P3L",
        },
        "UUID": LOG_UUID,
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

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(plistlib.dumps(workflow, fmt=plistlib.FMT_BINARY))
print(OUT, OUT.stat().st_size, "bytes")

# Read the file back, so what is printed is what was written.
written = plistlib.loads(OUT.read_bytes())
print("\nTriggers:")
pprint.pprint(written["WFWorkflowTriggers"], sort_dicts=False, width=110)
print("\nAction:")
pprint.pprint(written["WFWorkflowActions"], sort_dicts=False, width=110)
