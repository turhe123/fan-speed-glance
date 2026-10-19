# FanSpeedGlance — specification

**Tagline:** A menu bar readout of every fan's RPM with a short history sparkline and quiet or loud alerts.

**Category:** System Monitoring

**Inspired by (paid):** Macs Fan Control Pro ($14.95 one-time)

**Frameworks:** SwiftUI, AppKit, IOKit, UserNotifications, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: Macs Fan Control is a well known fan utility that shows fan speeds and temperatures and, in the Pro license, lets you set custom curves and presets. The free version is hugely popular and the Pro license is a one-time purchase that a file site lists at 14.95, which shows many people pay for fan tooling. Writing fan speeds needs a privileged helper and risks hardware, so our clean-room version is strictly a read-only monitor: it shows what the fans are doing and warns about unusual behavior.

Feature set, scoped to about 250 to 400 lines: detect the number of fans, read the current, minimum and maximum RPM for each, show a percent of maximum, keep a rolling ten minute history in memory and draw a sparkline, and offer two optional alerts: one when a fan exceeds a chosen percent of its maximum for more than two minutes, and one when a fan that should be spinning reads zero for a minute while the thermal state is fair or worse. The menu bar title can show the highest RPM, a fan glyph, or both.

UI spec: a MenuBarExtra with window style. The popover lists each fan with a name such as Left or Right, a horizontal gauge, the RPM number and the sparkline. At the top is the system thermal state shown as Nominal, Fair, Serious or Critical with a colored dot. Below is a footer with Settings and Quit. Settings has a title style picker, a refresh interval of one, two or five seconds, alert thresholds, a toggle for notifications and a launch at login toggle. Empty state for fanless Macs such as MacBook Air: the popover says This Mac has no fans and shows only the thermal state, which still helps. Keyboard shortcut Command comma for Settings.

Technical approach: open the AppleSMC service with IOServiceGetMatchingService and IOServiceOpen, then read keys with IOConnectCallStructMethod using the standard key info and read key selectors. The relevant keys are the fan count key, and per-fan actual, minimum and maximum speed keys, whose values are decoded according to the type string the SMC returns, which is fixed point or floating point depending on the machine. Keep the key reading code in one small struct so a failure can be handled in one place. Thermal state comes from ProcessInfo.processInfo.thermalState together with the thermal state change notification. Use a Timer on the main run loop with the user's interval and pause it when the popover is closed and the menu bar title is static. Notifications use UNUserNotificationCenter with a one time authorization request. Settings persist in AppStorage and launch at login uses SMAppService. No Accessibility, Screen Recording or Microphone permissions are needed, and the app does not require root for read access.

Edge cases and error handling: if the SMC cannot be opened, show a clear unsupported message instead of zero values. Treat implausible readings, such as negative values or numbers over twenty thousand, as a failed read and keep the previous value. Start alert timers only after two consecutive qualifying samples so brief spikes after wake do not cause noise. Round displayed RPM to the nearest ten to avoid flicker in the menu bar, and use fixed width digits so the status item does not jiggle.
