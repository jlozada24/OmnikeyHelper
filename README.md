# OmnikeyHelper

<img src="docs/icon.png" width="112" alt="Purple OmnikeyHelper icon">

**Scan a card. Send Return.** Configure your OMNIKEY 5027 directly on a Mac.

## Download

**[Download OmnikeyHelper for Mac](https://github.com/jlozada24/OmnikeyHelper/releases/latest/download/OmnikeyHelper.dmg)**

macOS 12 or later · Apple silicon and Intel · Developer ID signed and Apple-notarized

Open the DMG and drag **OmnikeyHelper** onto the **Applications** shortcut. Eject the disk image, then open OmnikeyHelper from Applications. No installer or administrator password is needed. This is an initial hardware-validation release: offline checks pass, but a real scan still needs validation after macOS permissions are granted.

## Quick setup

1. Connect one OMNIKEY 5027 and remove the card.
2. Open OmnikeyHelper and click **Inspect Reader**.
3. If access is denied, quit the app, enable it in **System Settings → Privacy & Security → Input Monitoring**, and reopen it. Use **+** to add the app from Applications if it is missing.
4. Click **Inspect Reader → Add Return**. A backup is saved before any settings change.
5. Click the test field and scan a card. The field should clear and show **Return received**. Do not press Return manually during the test.
6. Quit the app. The reader retains the setting.

[Releases](https://github.com/jlozada24/OmnikeyHelper/releases) · [Report an issue](https://github.com/jlozada24/OmnikeyHelper/issues)

Native OMNIKEY 5027 Return configuration for macOS 12+, Apple silicon and Intel. No third-party runtime dependencies. Independent utility, not an HID Global product.

## Use

Move the app to Applications. Connect exactly one 5027, remove cards, and click Inspect Reader. If macOS denies access, quit the app and enable OmnikeyHelper in System Settings > Privacy & Security > Input Monitoring. Use the + button to add the app if absent. Reopen and inspect again.

Click Add Return, then click the test field and scan a card. Return clears that field and displays a confirmation. Do not press Return manually during this test. Quit after setup; the reader retains its setting.

## Backups

JSON backups are stored in `~/Library/Application Support/OmnikeyHelper/Backups`. They include the reader serial and all seven keyboard-output fields in all three slots. This is a keyboard-settings backup, not a complete firmware/configuration/key export. No card numbers are saved.

Restore Backup restores only the two stroke fields changed by this app. It requires the same reader serial and unchanged card/output settings, and saves another backup before restoring. Ambiguous overlapping card types, full buffers, and unusual custom suffixes are refused. Already-configured trailing Enter is left unchanged.

The app reads back staged settings and reconnects after applying them to verify persistence. If verification fails, it reports uncertainty; reconnect and inspect before retrying. Reconnecting also restores keyboard mode. Close other reader software when configuring.

## Build and tests

Run `./build.sh` with Xcode Command Line Tools installed. Output is `../OmnikeyHelper.app`. Uses AppKit, IOKit and PCSC. Both architectures are compiled.

Executable options: `--self-test` (offline, no device access), `--inspect` (read keyboard settings), and `--apply` (back up, add Enter, save and verify). Terminal hardware permissions can be attributed to the hosting app; colleagues should use the GUI.

Both architecture builds and offline tests passed. A hardware attempt reached a 5027 but macOS denied IOHIDDeviceOpen with error 0xe00002e2. No reader settings were changed. Hardware read/write and a real scan still require validation after permission is granted. Intel execution and the visual GUI have not been interactively tested. Notarization verifies distribution requirements, not hardware behavior.

## Protocol references

- HID developer guide PLT-03824 A.1, sections 2.1.2, 3.1.6, 9.4.1 and 9.8: https://www.hidglobal.com/documents/omnikey-5027-software-developer-guide
- Official protocol examples: https://github.com/hidglobal/HID-OMNIKEY-Sample-Codes
- Apple IOKit and PCSC SDK headers.

No Windows binary was reverse engineered. Enter is the documented post-stroke byte 0x01, not the separate carriage-return character.

## Updating from OmniReturn

OmnikeyHelper is the renamed app. Grant permission to the new app separately. Earlier backups remain in `~/Library/Application Support/OmniReturn/Backups`; select them manually in Restore Backup if needed. The backup format is unchanged.

## macOS connection compatibility

Version 1.0.2 uses a nonzero RAW protocol mask for direct PC/SC connections. This addresses error `0x80100011` (invalid value) seen with the previous zero-mask connection. Input Monitoring access alone does not resolve that connection error. This fix still requires hardware confirmation.

Reference: https://github.com/smartcardservices/smartcardservices/blob/master/SmartCardServices/src/PCSC/winscard_clnt.c

## Driver feature discovery (1.0.3)

The app queries PC/SC Part 10 for the driver-provided CCID escape control code before sending configuration commands, instead of always assuming the legacy 3500 code. If the driver does not advertise one, the legacy code remains the fallback. Errors now show the transport and control code for troubleshooting. The footer has been removed. Feature parsing tests cover byte order, truncation and malformed records. Hardware behavior remains unverified.

## Current hardware-test result

A desktop test of 1.0.3 successfully opened the 5027 and discovered the advertised escape control code `0x42000001`, but the active macOS driver rejected the first configuration read with `0x80100004`. No settings were written. Automatic Return setup is therefore **not yet working on this tested configuration**. Testing the alternate bundled CCID driver is the next diagnostic step; it has not yet been verified as a fix.
