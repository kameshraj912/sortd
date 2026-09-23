"""Build the ready-made Sortd Apple Pay shortcut.

The Wallet automation hands Shortcuts a Transaction object. Sortd's action is
filled from it two ways at once, because only one of them can be checked from
here:

1. Three property mappings (Amount, Merchant, Card or Pass). Exact, but they
   depend on Apple's property names, which are not documented and cannot be
   read from a simulator — a Wallet automation needs a real card, so a
   simulator refuses to build one at all.
2. A Text action holding the whole transaction, passed to `transaction`.
   Shortcuts renders any variable to text here, so this works whatever the
   properties are called, and `WalletTapText.parse` pulls the pieces out.

`LogWalletTapIntent.handle` parses the text first and then lets any non-empty
field from (1) win, so the two agree when both work and (2) carries it when
(1) comes back blank.

Then sign it:
    shortcuts sign --mode anyone --input <out> --output site/apple-pay.shortcut
"""

import plistlib, pathlib, uuid

OUT = pathlib.Path("/private/tmp/claude-501/shortcut/Log Apple Pay in Sortd.shortcut")

TEXT_UUID = str(uuid.uuid4()).upper()
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


# Text action: one attachment at position 0 that is the whole Shortcut Input.
# The placeholder character is what Shortcuts puts where a variable sits.
whole_input_as_text = {
    "WFWorkflowActionIdentifier": "is.workflow.actions.gettext",
    "WFWorkflowActionParameters": {
        "UUID": TEXT_UUID,
        "WFTextActionText": {
            "Value": {
                "string": "￼",
                "attachmentsByRange": {
                    "{0, 1}": {"Type": "ExtensionInput"},
                },
            },
            "WFSerializationType": "WFTextTokenString",
        },
    },
}

log = {
    "WFWorkflowActionIdentifier": "com.kameshraj.spend.LogWalletTapIntent",
    "WFWorkflowActionParameters": {
        "AppIntentDescriptor": {
            "AppIntentIdentifier": "LogWalletTapIntent",
            "BundleIdentifier": "com.kameshraj.spend",
            "Name": "Sortd",
            "TeamIdentifier": "None",
        },
        "UUID": LOG_UUID,
        # The safety net: whatever the transaction looks like, as text.
        "transaction": token({
            "Type": "ActionOutput",
            "OutputUUID": TEXT_UUID,
            "OutputName": "Text",
        }),
    },
}

workflow = {
    "WFWorkflowClientVersion": "3000",
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
    "WFWorkflowTypes": ["Watch"],
    "WFWorkflowActions": [whole_input_as_text, log],
    # No WFWorkflowUnifiedTriggers: an embedded Wallet trigger does not
    # survive the import (the trigger count stayed put), and leaving it in
    # only makes the file look like it sets up something it does not.
}

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(plistlib.dumps(workflow, fmt=plistlib.FMT_BINARY))
print(OUT, OUT.stat().st_size, "bytes")
