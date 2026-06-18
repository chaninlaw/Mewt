# Mewt Mic — App Store Connect Listing

Copy-paste ready for submission. Fields below match App Store Connect's "App Information" and "Version Information" sections.

---

## App Name (30 chars max)

```
Mewt Mic
```

(8 / 30)

---

## Subtitle (30 chars max)

```
Menu-bar mic mute for macOS
```

(27 / 30)

---

## Primary Category

`Utilities`

## Secondary Category

`Productivity`

> Note: `MARKETING.md` listed Entertainment as secondary, but **Productivity**
> aligns better with the actual use case (meetings, work). Reviewer may flag
> Entertainment as off-brand for a mic utility. Recommend Productivity.

---

## Keywords (100 chars max, comma-separated, NO spaces after commas)

```
mute,microphone,meeting,menu bar,push to talk,hotkey,mic indicator,toggle,privacy
```

(81 / 100)

**Notes**:

- "Mic" is already in app name — Apple search matches it without spending a keyword.
- Avoided naming competitor apps (Zoom/Meet/Discord) — Apple has rejected listings for that.
- "mute" + "microphone" covers the dominant search intent.

---

## Promotional Text (170 chars max — can be updated WITHOUT resubmission)

```
A privacy-first menu-bar mic mute. One hotkey, system-wide silence. No account, no cloud, no audio ever leaves your Mac.
```

(124 / 170)

> Use this field for launch announcements, sales, or feature flags later
> without filing a new build.

---

## Description (4000 chars max)

```
Mewt Mic is a privacy-first menu-bar mic mute. Toggle your microphone system-wide with a hotkey or one click — no accounts, no cloud, no audio ever leaves your Mac.

WHY MEWT?

A live mic indicator you can trust. Mewt sits quietly in the menu bar with a cat mascot that shows your current state at a glance: unmuted, talking, or muted. No more guessing whether your mic is hot in a meeting.

ONE-TAP CONTROL

• Left-click the menu-bar icon to open the popover with a Mute button and a real-time input level meter.
• Right-click to toggle mute instantly without opening anything.
• Global hotkey: ⌥M to toggle, or hold ⌥Space for push-to-talk.
• Customize hotkeys to whatever fits your fingers.

SYSTEM-WIDE MUTE

When you mute in Mewt, you are muted everywhere. The app uses CoreAudio to silence your microphone at the operating-system level — so every other app stops receiving audio simultaneously. The input-level meter is your source of truth: if the bar stays flat while you talk, you are muted.

PRIVACY YOU CAN VERIFY

Mewt does nothing it does not need to. There is no account, no sign-in, no analytics, no crash reporting, and no network activity of any kind. Audio is processed in memory only — never recorded, written to disk, or transmitted. The privacy manifest declares zero data collection.

DESIGNED FOR MEETING-HEAVY WORK

• Push-to-talk for the occasional ad-hoc moment when you usually stay muted.
• Quiet menu-bar accessory: no Dock icon, no nagging notifications.
• Light on memory and battery.
• Works fully offline.

REQUIREMENTS

macOS 14 (Sonoma) or later.

Privacy policy: https://mewt.nin-070.workers.dev/privacy.html
Support: https://mewt.nin-070.workers.dev/
```

(~1660 / 4000)

**Rules followed**:

- No mention of paid tiers (Plus / Studio) — 1.0 ships free.
- No mention of "talk-while-muted detection" — feature retired.
- Hook (first ~170 chars) stands alone as the snippet.
- All-caps section headers render bold in App Store typography.

---

## What's New in This Version (release notes)

```
First public release of Mewt Mic.

• System-wide microphone mute via CoreAudio.
• Menu-bar accessory with cat mascot showing live mic state.
• Global hotkeys: ⌥M to toggle, ⌥Space for push-to-talk.
• Real-time input level meter.
• Customizable shortcuts.
• Zero data collection — no account, no network, no analytics.
```

---

## Privacy Practices (App Privacy section)

| Question               | Answer                                          |
| ---------------------- | ----------------------------------------------- |
| Data used to track you | **None**                                        |
| Data linked to you     | **None**                                        |
| Data not linked to you | **None**                                        |
| Privacy policy URL     | `https://mewt.nin-070.workers.dev/privacy.html` |

Declare: **Data Not Collected**.

---

## Support / Marketing URLs

| Field                | Value                                                       |
| -------------------- | ----------------------------------------------------------- |
| Support URL          | `https://mewt.nin-070.workers.dev/`                         |
| Privacy Policy URL   | `https://mewt.nin-070.workers.dev/privacy.html`             |
| Marketing URL (opt.) | leave blank — same as Support URL until landing page exists |

---

## Age Rating

`4+` (no objectionable content)

---

## Pricing & Availability

- **Price tier**: Free
- **Availability**: All territories
- **In-App Purchases**: None (do **not** configure IAP for 1.0)
- **Game Center**: Off
