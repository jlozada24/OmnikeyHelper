# OmnikeyHelper

<img src="docs/icon.png" width="112" alt="Purple OmnikeyHelper icon">

**Scan a card. Send Return.** Configure an OMNIKEY 5027 directly on a Mac.

## Download

**[Download OmnikeyHelper for Mac](https://github.com/jlozada24/OmnikeyHelper/releases/latest/download/OmnikeyHelper.dmg)**

macOS 12+ · Apple silicon and Intel · Developer ID signed and Apple-notarized

Open the DMG and drag **OmnikeyHelper** onto **Applications**. Eject the disk image and launch the app from Applications. There is no installer package.

## Setup

1. Connect exactly one OMNIKEY 5027.
2. Click **Inspect Reader** and approve the macOS administrator prompt. The app reads the current keyboard settings.
3. Click **Add Return** and authorize the change. The app backs up the existing settings, adds Enter to the active card configurations, and reads the saved settings back.
4. **Unplug and reconnect the reader.** This restores normal keyboard input after configuration and checks that the settings survive a power cycle. You can dismiss macOS's keyboard-identification assistant if it appears.
5. Click the app's test field and scan a card. **Return received** confirms that the scan submitted and cleared the field. Do not press Return manually during the test.
6. Quit the app. The reader retains the setting; no background app is needed.

If Return is already configured, Add Return is disabled. USB mode changes can briefly remove the reader; the app retries capture before issuing configuration commands. If it still cannot connect, unplug/reconnect and inspect again.

## Why administrator authorization?

On the tested Mac, the standard PC/SC driver rejected configuration commands. Version 1.1 uses direct USB capture, for which macOS requires administrator authorization. The signed helper temporarily captures **only the 5027**, performs the requested operation, and releases it. It does not change the system-wide driver preference, install a driver, or install a persistent background service. Users without administrator access need their IT administrator to configure the reader.

The app does not need Input Monitoring permission for this transport. Older versions requested it for a different approach.

## Backups and restore

Backups are in `~/Library/Application Support/OmnikeyHelper/Backups`. They contain the reader serial identifier and all seven keyboard-output fields for all three slots. This is a keyboard-settings backup, not a full firmware/key export. No scanned card numbers are saved.

**Restore Backup** restores the two stroke fields changed by OmnikeyHelper. It requires the same reader and unchanged card/output settings, and saves another backup first. File access for backups runs with the configuring user's effective identity, not root. After restoring, reconnect the reader.

Existing prefixes and suffixes are preserved where there is space. Full buffers, ambiguous output combinations, and unusual custom suffixes are refused rather than overwritten. Existing trailing Enter is left unchanged.

## Validation

The direct USB transport was tested on a physical OMNIKEY 5027. It read all keyboard settings, saved a backup, added Return to iCLASS, ISO14443A and ISO15693 slots, and read the values back after saving. A second run confirmed persistence and made no changes. After unplug/replug, a real card scan produced **Return received** in the app. The integrated GUI authorization and inspection path also successfully read those settings.

Both architecture builds and offline protocol/transformation tests pass. Intel hardware and every supported macOS version have not been tested. Restore logic is included but has not been exercised on hardware.

## Build

With Xcode Command Line Tools installed, run `./build.sh`. Output is `../OmnikeyHelper.app`, including the universal configuration helper. No third-party runtime libraries are bundled.

The app executable's `--self-test` option performs offline tests without accessing hardware. The helper supports `--native-inspect`, `--native-apply` and `--native-restore`; normal users should use the GUI. Administrator authorization is required for capture.

The GUI verifies the helper's Developer ID signature and identifier before launching it. Distribution builds must sign the helper with identifier `com.javierlozada.omnikeyhelper.configure` and the configured team requirement in `Authorize.c`, then sign the enclosing app. A developer using another signing team must update that requirement. The one-shot launcher currently uses the deprecated Authorization Services execution API; a future modernization can use ServiceManagement. No authorization is silently obtained or reused across launches.

## References

- [HID OMNIKEY 5027 developer guide](https://www.hidglobal.com/documents/omnikey-5027-software-developer-guide): mode switching, Enter byte 0x01, keyboard fields and applying settings.
- [HID protocol examples](https://github.com/hidglobal/HID-OMNIKEY-Sample-Codes).
- [Apple USB capture requirements](https://developer.apple.com/documentation/iousbhost/iousbhostobjectinitoptions/devicecapture).

Independent utility, not an HID Global product. No Windows binary was reverse engineered. Earlier OmniReturn backups use the same format and can be selected manually from its previous backup folder.
