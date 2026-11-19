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

## 5. Fill in the 1.0 version and submit (current UI, checked against Apple Help Nov 2026)

Since **15 Jul 2026** the version page no longer has an "In-App Purchases and Subscriptions" picker. IAPs now join the version through a **draft submission**: every IAP and the 1.0 version get **Add for Review** into the *same* draft, then the draft is submitted once. Copy for every field lives in `tasks/app-store-listing.md`.

Sources: [Submit an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase), [Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app), [Manage your App Store assets](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-your-app-store-assets), [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy), [Release notes](https://developer.apple.com/help/app-store-connect/release-notes/).

### 5a. App-level pages (sidebar, outside the version)

1. **App Information** (sidebar → General): Primary Category **Utilities**, Secondary **Productivity**; Content Rights → *does not contain third-party content*; **Age Rating** → Edit → answer the questionnaire (all None/No) → expect 4+. Save
2. **App Privacy** (sidebar): Privacy Policy URL `https://mewt.nin-070.workers.dev/privacy.html` → **Get Started** → *No, we do not collect data from this app* → Save → **Publish** (top right) → Publish
3. **Pricing and Availability** (sidebar): Price **Free (0.00)**, Availability all countries/regions. Save
4. **App Compliance** (new page, Nov 2026, holds regulations/permits): nothing applies to Mewt; only open it if ASC flags it as incomplete

### 5b. macOS version page (sidebar → macOS App → **1.0 Prepare for Submission**)

1. **Product Page Information → App Previews and Screenshots** tab → **Mac** tab → drag in the 6 PNGs from `tasks/screenshots/` in order 01…06. (Or upload them in sidebar **Asset Library** → ＋ → *Previews and Screenshots*, then use **Browse Assets** here)
2. Same section, English (U.S.): **Promotional Text**, **Description**, **Keywords**, **Support URL**, Marketing URL blank. There is no *What's New* field on a first version; that text waits for 1.0.1
3. **General / Version information**: Copyright `2026 <your legal name>` (shown on the store as-is); Version `1.0`
4. **Build** → **Add Build** → pick **1.0 (1)** → answer export compliance (uses no non-exempt encryption → *None of the algorithms mentioned above*) if asked
5. **App Review Information**: *Sign-in required* **off**; contact name, email, phone **in international format** (`+66 …`); **Notes**: paste the block from `tasks/pre-submission.md` §6
6. **Version Release**: *Manually release this version* (safest for 1.0) or automatic
7. **Save** (top right)

### 5c. Put everything into one draft submission

1. Sidebar → Monetization → **In-App Purchases** → open **Tip Treat** → **Add for Review** → **Create New Submission** → platform **macOS**, version **1.0**
2. Open **Tip Tuna Can** → **Add for Review** → choose the **existing draft** (do *not* create a new one)
3. Same for **Tip Cat Tower**
4. Back on the **1.0** version page → **Add for Review** (top right) → existing draft. Version status becomes *Ready for Review*
5. Click **Draft Submissions** (bottom right) or sidebar **App Review** → check it lists macOS App 1.0 + 3 IAPs → **Submit for Review**

If **Add for Review** on an IAP is greyed out, it's missing something (usually the review screenshot or a localization) — the product page shows what. If ASC rejects the draft, the forum workaround is to open the existing draft rather than *Create New Submission*.

Done when: App Review shows one submission *Waiting for Review* containing macOS 1.0 and the three tips.
