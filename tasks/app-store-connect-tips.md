# App Store Connect — Tip IAP Setup

Status 2026-11-19: Paid Applications Agreement, banking and tax are done. **Tip Treat** (`com.chaninlaw.Mewt.tip.treat`) already exists. Still to create: **Tuna Can** and **Cat Tower**, plus review screenshots for all three. Then attach all three to the 1.0 version.

Values must match `Tips.storekit` and `TipStore.productIDs` exactly. A product ID is **permanent**: once saved it can't be renamed or reused, even after deletion. Paste the IDs; don't type them.

---

## 1. Create Tuna Can

App Store Connect → Apps → **Mewt Mic** → sidebar *Monetization* → **In-App Purchases** → **＋**

| Field | Value |
|---|---|
| Type | **Consumable** |
| Reference Name | `Tip Tuna Can` |
| Product ID | `com.chaninlaw.Mewt.tip.tuna` |

→ **Create**, then on the product page:

1. **Availability**: all countries/regions (same as Treat)
2. **Price Schedule** → Add Pricing → base country **Thailand**, price **฿99** → Next → accept the generated prices for other storefronts → Confirm
3. **App Store Localization** → ＋ English (U.S.)
   - Display Name: `Tuna Can`
   - Description: `A medium tip for Mewt's developer` (33/45 chars, contains "tip")
4. **Review Information**
   - Screenshot: see step 3 below
   - Review Notes: `Optional tip. Unlocks no content or features; all of Mewt is free. Found in the popover: click the heart icon in the footer → Support Mewt.`
5. **Save**. Status should become **Ready to Submit** once the screenshot is in

## 2. Create Cat Tower

Same as step 1, with these values:

| Field | Value |
|---|---|
| Type | **Consumable** |
| Reference Name | `Tip Cat Tower` |
| Product ID | `com.chaninlaw.Mewt.tip.tower` |
| Price (Thailand base) | **฿349** |
| Display Name (en-US) | `Cat Tower` |
| Description (en-US) | `A generous tip for Mewt's developer` (35/45 chars) |

## 2b. Check Tip Treat matches

Open the existing Treat product and confirm:
- Type is **Consumable**. If it's *Non-Consumable*, the type can't be changed; tell Claude before doing anything else
- Price ฿35 (Thailand base)
- en-US Display Name `Treat`, Description `A small tip for Mewt's developer`
- Review Notes the same as above

## 3. Review screenshot (all three)

Apple wants one screenshot per IAP showing the purchase in the app. The same image works for all three: **`tasks/screenshots/06-support.png`** (the Support page with the 3 tip cards, 2880×1800, no alpha).

1. If it's missing or the UI changed, regenerate: `scripts/screenshots.sh`
2. Upload it under **Review Information → Screenshot** on each of the three products

## 4. Sandbox tester (for the Pass B test)

Users and Access → **Sandbox** → Test Accounts → ＋
- Use a fresh email you control (a `+alias` of your Gmail works), region **Thailand**
- After creating: open the tester → **Interrupt Purchases: Off**

On the Mac: System Settings → App Store → *Sandbox Account* → Sign In with the tester.

## 5. Attach to the 1.0 submission

The first IAPs must go out **with** an app version. They can't be submitted alone.

1. Apps → Mewt Mic → **macOS App → 1.0 Prepare for Submission**
2. Scroll to **In-App Purchases and Subscriptions** → **＋ / Select** → tick Treat, Tuna Can, Cat Tower → Done
3. App Review Information → Notes: paste the block from `tasks/pre-submission.md` §6 (it already covers the tips)
4. When the build is uploaded and everything in `tasks/pre-submission.md` is ticked → **Add for Review → Submit**

Done when: all three IAPs show **Ready to Submit** and they're listed on the 1.0 version page.
