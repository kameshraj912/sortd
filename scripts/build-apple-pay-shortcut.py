"""Build the ready-made Sortd Apple Pay shortcut.

The Wallet automation hands Shortcuts a Transaction object. Each field of
Sortd's action is filled with one property of that object, which is the part
people get wrong by hand.
"""

import plistlib, pathlib, uuid

OUT = pathlib.Path("/private/tmp/claude-501/shortcut/Log Apple Pay in Sortd.shortcut")


def input_property(name: str) -> dict:
    """Shortcut Input → one property of the Wallet transaction."""
    return {
        "Value": {
            "Type": "ExtensionInput",
            "Aggrandizements": [
                {"Type": "WFPropertyVariableAggrandizement", "PropertyName": name}
            ],
        },
        "WFSerializationType": "WFTextTokenAttachment",
    }


action = {
    "WFWorkflowActionIdentifier": "com.kameshraj.spend.LogWalletTapIntent",
    "WFWorkflowActionParameters": {
        "AppIntentDescriptor": {
            "AppIntentIdentifier": "LogWalletTapIntent",
            "BundleIdentifier": "com.kameshraj.spend",
            "Name": "Sortd",
            "TeamIdentifier": "None",
        },
        "UUID": str(uuid.uuid4()).upper(),
        "amount": input_property("Amount"),
        "merchant": input_property("Merchant"),
        "card": input_property("Card or Pass"),
    },
}

workflow = {
    "WFWorkflowClientVersion": "3000",
    "WFWorkflowMinimumClientVersion": 900,
    "WFWorkflowMinimumClientVersionString": "900",
    "WFWorkflowHasOutputFallback": False,
    "WFWorkflowHasShortcutInputVariables": True,
    "WFWorkflowIcon": {
        "WFWorkflowIconStartColor": 946986751,  # orange, like the app mark
        "WFWorkflowIconGlyphNumber": 59511,  # a receipt-ish glyph
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
    "WFWorkflowActions": [action],
    # iOS 26/27 keeps the automation trigger with the shortcut, so this
    # arrives ready to switch on instead of being built by hand.
    "WFWorkflowUnifiedTriggers": [
        {
            "WFTriggerIdentifier": "WFWalletTransactionTrigger",
            "WFTriggerSerializedParameters": {},
            "WFTriggerUUID": str(uuid.uuid4()).upper(),
        }
    ],
}

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(plistlib.dumps(workflow, fmt=plistlib.FMT_BINARY))
print(OUT, OUT.stat().st_size, "bytes")
