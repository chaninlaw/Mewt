# Research: App Review rules + StoreKit 2 tips in a menu-bar app

- Ticket: https://github.com/chaninlaw/Mewt/issues/3 (map: https://github.com/chaninlaw/Mewt/issues/2)
- Date: 2026-10-19
- Context: Mewt is a sandboxed `LSUIElement` macOS app (deployment target macOS 26.4). Its UI is an AppKit `NSPopover` (`behavior = .transient`) hosting SwiftUI through `NSHostingController` (`Mewt/Tray/TrayController.swift`). It has no network or analytics. Current entitlements are `app-sandbox` and `device.audio-input` only.
- Sources: Apple primary sources only (App Review Guidelines, Apple developer docs fetched from the DocC JSON behind developer.apple.com/documentation, App Store Connect Help). Two public App Store storefront pages were used as observations for pricing. Anything not verified is marked **UNVERIFIED**.

## TL;DR

| Question | Answer |
|---|---|
| Must tips use IAP? | Yes. Tips go through IAP, and 3.1.1 explicitly allows IAP for tipping the developer. 3.2.1(vii), the non-IAP exception for monetary gifts, covers person-to-person gifts in apps such as social apps and does not fit a developer tip jar. |
| IAP type | **Consumable.** A tip is "used once". Consumables need no restore UI and don't appear in `Transaction.currentEntitlements`. Family Sharing doesn't apply to them. |
| "Donation" wording | The guidelines never use "donate" or "donation". The nearby rules cover charity fundraising, which is banned in-app unless you are an approved nonprofit (3.2.2(iv)). Use "Tip" or "Support the developer" wording and make no charitable claims. This is an **inference**, not a documented rule. |
| First submission | The first consumable IAP **must be submitted together with a new app version**. |
| Metadata | Reference name (64 chars max), product ID (100 chars max, permanent), display name (2-30 chars), description (45 chars max), a review screenshot (Mac sizes, 16:10), and optional review notes (4000 chars max). The Paid Apps Agreement must be active. |
| Prices | Choose a base country and Apple generates the rest. Public storefronts show **฿35 / ฿179 / ฿349** next to **$0.99 / $4.99 / $9.99** for one app, but different THB values for another, so the exact mapping is **UNVERIFIED**. Read it in App Store Connect. |
| Purchase API on macOS | `PurchaseAction` (SwiftUI, macOS 14+), `Product.purchase(confirmIn: NSWindow)` (AppKit, macOS 15.2+), or StoreKit views like `ProductView`. The transient-popover behavior is **UNVERIFIED** and needs a prototype. |
| Transactions | Start a `Transaction.updates` listener at launch. Call `finish()` after "delivering", which for a tip means right after verification. |
| Testing | Use a local `.storekit` config selected in the scheme's Run options, plus `StoreKitTest`'s `SKTestSession` for automated tests. Neither needs the network. |
| Privacy | StoreKit is not a required-reason API category, and that rule targets iOS-family platforms, not macOS. Apple says "You are not responsible for disclosing data collected by Apple". If Mewt sends nothing off-device, "Data Not Collected" stays valid. |

## 1. Is IAP required? Is "donation" wording a risk?

**Guideline 3.1.1 In-App Purchase** ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase)):

> If you want to unlock features or functionality within your app, (by way of example: subscriptions, in-game currencies, game levels, access to premium content, or unlocking a full version), you must use in-app purchase.

> Apps may use in-app purchase currencies to enable customers to "tip" the developer or digital content providers in the app.

> Any credits or in-game currencies purchased via in-app purchase may not expire, and you should make sure you have a restore mechanism for any restorable in-app purchases.

**Guideline 3.2.1(vii)** ([link](https://developer.apple.com/app-store/review/guidelines/#acceptable)):

> Apps may enable individual users to give a monetary gift to another individual without using in-app purchase, provided that (a) the gift is a completely optional choice by the giver, and (b) 100% of the funds go to the receiver of the gift. However, a gift that is connected to or associated at any point in time with receiving digital content or services must use in-app purchase.

This is the exception for gifts between users. A tip to the developer of the app being used is tied to the digital service the app provides, and Apple takes its commission, so 100% does not reach the receiver. A tip jar therefore falls under the 3.1.1 tipping bullet, which means IAP. This reading is an inference, but it is the conservative one.

**Guideline 3.2.2(iv)** ([link](https://developer.apple.com/app-store/review/guidelines/#unacceptable)) lists as unacceptable:

> Unless you are an approved nonprofit or otherwise permitted under Section 3.2.1 (vi) above, collecting funds within the app for charities and fundraisers. Apps that seek to raise money for such causes must be free on the App Store and may only collect funds outside of the app, such as via Safari or SMS.

**Wording risk.** The words "donate" and "donation" appear nowhere in the guidelines. The rules nearest to that concept are 3.2.1(vi) (approved nonprofits) and 3.2.2(iv) (charities and fundraisers). A reviewer who sees "Donate" from an individual developer could read it as fundraising. Apple's own wording is "tip". **Recommendation:** label the feature "Tip" or "Support Mewt" or "Buy the developer a coffee". Avoid "donate", "donation", and "charity". Make clear that tips unlock nothing. A tip that unlocked a feature would turn the tip into a feature unlock under 3.1.1. The risk itself is **inferred from the guideline structure**, not stated by Apple.

**Restore.** Restore is only required for "restorable" IAPs. Consumables are not restorable (see section 2), so a tips-only app needs no "Restore Purchases" button. Inference from 3.1.1 combined with the StoreKit docs below.

## 2. Consumable vs non-consumable

[App Store Connect Help: In-App Purchase types](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-types):

> **Consumable**: A product that is used once, after which it becomes depleted and must be purchased again. Example: fish food in a fishing app.
> **Non-Consumable**: A product that is purchased once and does not expire or decrease with use.

Tips are repeatable and grant nothing lasting, so they should be **consumable**. A non-consumable tip could be bought only once per Apple Account, and it would show up as an entitlement.

StoreKit behaviour for consumables:

- [`Transaction.currentEntitlements`](https://developer.apple.com/documentation/storekit/transaction/currententitlements): "Consumable Apple In-App Purchases also don't appear in the current entitlements. To get transactions for unfinished consumables, use the `unfinished` or `all` sequences."
- [`Transaction.all`](https://developer.apple.com/documentation/storekit/transaction/all): by default the history "excludes finished consumables (unless refunded or revoked). To get all possible transactions, including all finished consumables, set the `SKIncludeConsumableInAppPurchaseHistory` property list key to `true`." This is only relevant if we want a "you've tipped N times, thank you" display. The data stays local because StoreKit supplies it from the device.
- Family Sharing is offered only "for non-consumable in-app purchases and auto-renewable subscriptions" ([Setting up StoreKit Testing in Xcode](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode)). It doesn't apply to tips.

## 3. Required IAP metadata and first-submission rules

[App Store Connect Help: In-App Purchase information](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information):

| Field | Rule (quoted / paraphrased) |
|---|---|
| Reference Name | Internal only, at most 64 characters, editable without review. |
| Product ID | Letters, numbers, `-`, `.`, `_`, at most 100 characters. "not editable after you save", and it "can't be reused ... even if you delete the original". "You need separate identifiers for In-App Purchases in your iOS apps and your macOS apps." |
| Display Name (localizable) | "at least two characters and no more than 30 characters." |
| Description (localizable) | "no more than 45 characters." |
| App Review Screenshot | "clearly shows the item or service being offered ... used for review only". It must meet a screenshot spec your app supports. Once uploaded it can be replaced but not removed. |
| Review Notes | Optional, at most 4000 characters. |

Mac screenshot sizes ([Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)): 16:10 at 1280x800, 1440x900, 2560x1600, or 2880x1800. JPEG or PNG, no alpha channel. The review screenshot should show the tip UI with the products visible.

Creating the IAP: Apps > Monetization > In-App Purchases > (+) > Consumable, then a reference name and product ID ([Create consumable or non-consumable IAPs](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases)). Metadata changes "may take up to 1 hour" to show up in sandbox.

**First submission** ([Submit an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase)):

> The first consumable, non-consumable, auto-renewable subscription, and non-renewing subscription In-App Purchase of each type must be submitted with a new app version. After the first item of a given type is approved, you can submit additional items of that type without a new app version, as long as your app has at least one approved app version at the time of submission.

> The app version, subscription group, and every subscription or In-App Purchase you want reviewed together must all be added to the same draft submission before you click Submit for Review.

Because 1.0 is scoped as free with no IAP, tips will first ship in a later version (for example 1.1), with every tip product in the same draft submission. After that, more tip tiers can be added without a binary update.

**Agreement** ([Sign and update agreements](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements)): "To sell your apps on the App Store or offer In-App Purchases, the Account Holder must sign the Paid Apps Agreement." Also: "You won't be able to create a new app or In-App Purchase until you've agreed to the most recent version of the Paid Apps Agreement." The agreement depends on tax and banking information. That last point comes from third-party guides and is **not verified** against an Apple page.

## 4. Price tiers (THB / USD)

[Set a price](https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price) (this page covers app pricing, and IAPs use the same price-point system):

> Choose from up to 800 price points by default, and request to access an additional 100 higher price points (up to $10,000).

> You can set a price for the country or region you're familiar with as the basis for automatically generating prices across the other 174 storefronts and 43 currencies. Automatically generated prices account for foreign exchange rates and certain taxes, and follow the most common pricing convention for each country or region.

> Prices for your base country or region won't be adjusted by Apple as taxes and foreign exchange rates change.

Any storefront can be overridden by hand. Apple then stops adjusting that storefront.

**Observed THB/USD pairs (UNVERIFIED as Apple's default mapping).** Public App Store pages fetched on 2026-10-19:

| USD (US store) | Clash of Clans (TH store) | Plague Inc. (TH store) |
|---|---|---|
| $0.99 | ฿35 | ฿29 |
| $1.99 | - | ฿79 |
| $2.99 | - | ฿99 |
| $4.99 | ฿179 | - |
| $9.99 | ฿349 | ฿399 |
| $19.99 | ฿729 | - |

The two apps disagree, which shows the THB values depend on the developer's base country and any manual overrides. Public pages can't confirm Apple's auto-generated equivalents. What these pages do confirm is that **฿29, ฿35, ฿39, ฿49, ฿79, ฿99, ฿149, ฿179, ฿299, ฿349, ฿399 are all valid THB price points today**, so the ฿35-฿350 range in the ticket fits.

**Recommendation for the "Tip lineup & pricing" decision:** the developer and many early users are Thai, so set **Thailand as the base country** and pick round baht points directly, for example ฿35 / ฿99 / ฿349. Then read the generated USD column in App Store Connect. Alternatively, set a US base at $0.99 / $2.99 / $9.99 and read the THB column. Either way the actual mapping has to be read in App Store Connect once logged in. Proceeds and commission rates are out of scope here (not researched).

## 5. Purchase sheet from a menu-bar popover

### API choice (Apple docs)

- [`PurchaseAction`](https://developer.apple.com/documentation/storekit/purchaseaction) (`@Environment(\.purchase)`, macOS 14+): "The purchase action you get from the environment automatically includes the UI context. It presents the confirmation UI in proximity to the scene in which the view displays."
- [`Product.purchase(confirmIn:options:)`](https://developer.apple.com/documentation/storekit/product/purchase(confirmin:options:)-8eai6), macOS **15.2+**: `func purchase(confirmIn window: NSWindow, options: Set<Product.PurchaseOption> = []) async throws -> Product.PurchaseResult`.
- [`Product.purchase(options:)`](https://developer.apple.com/documentation/storekit/product/purchase(options:)) recommends: "Use `PurchaseAction` for apps that use SwiftUI on any platform ... Use `purchase(confirmIn:options:)` for apps that run on macOS and use AppKit. Use `purchase(options:)` for apps that runs on watchOS." **Apple contradicts itself here.** The `PurchaseAction` page still says "Use `purchase(options:)` if your app runs on watchOS or macOS." The newer guidance is the window-anchored API.
- StoreKit views (`ProductView`, `StoreView`): "StoreKit manages the purchase action automatically, including presenting the purchase confirmation UI." (same page)

With a macOS 26.4 deployment target, every one of these is available.

### Popover caveats (UNVERIFIED, needs the UI prototype)

Apple doesn't document how any of these behave inside an `NSPopover` in an `LSUIElement` app. Hypotheses to test:

1. **No SwiftUI scene.** Mewt mounts SwiftUI in an `NSHostingController` inside an `NSPopover`, not a SwiftUI `Scene`, so the "UI context" `PurchaseAction` relies on may be missing or may resolve to the popover's private window.
2. **Transient dismissal.** `popover.behavior = .transient` closes the popover when the user interacts outside it. The system confirmation sheet or Apple Account sign-in prompt can take focus and close the popover partway through a purchase. The purchase `Task` might survive this, but any UI waiting on the result would be gone.
3. **Activation.** An accessory (`LSUIElement`) app may need `NSApp.activate()` so the sheet comes to the front.

Mitigations to try in the prototype, in order of simplicity:

- **A.** While a purchase is in flight, switch `popover.behavior` to `.applicationDefined` (or `.semitransient`), call `product.purchase(confirmIn: popoverWindow)`, and restore the behavior afterwards.
- **B.** Present the tip jar in a small dedicated `NSWindow` (an "About / Support Mewt" window), call `NSApp.activate()`, and use `purchase(confirmIn: thatWindow)` or a `ProductView` in that window. This is the most robust option, at the cost of one extra window.
- **C.** Use `ProductView` directly in the popover and let StoreKit handle presentation. It is the least code, but subject to caveats 1 and 2.

Community reports (Apple Developer Forums) don't settle the question: [StoreKit purchase windows very buggy on macOS](https://developer.apple.com/forums/thread/774414) reports clipped buttons and flicker in the verification popups and has no Apple reply. [Mac IAPs not showing in production](https://developer.apple.com/forums/thread/696173) is not popover-specific. No primary source covers menu-bar apps.

### Transaction handling (Apple docs)

- [`Transaction.updates`](https://developer.apple.com/documentation/storekit/transaction/updates): "Create a `Task` to iterate through the transactions from the listener as soon as your app launches. If your app has unfinished transactions, the `updates` listener receives them once, immediately after the app launches. Without the `Task` to listen for these transactions, your app may miss them." It also delivers Ask to Buy approvals and purchases made on other devices. A successful purchase on the same device comes back through `PurchaseResult.success` instead.
- [`finish()`](https://developer.apple.com/documentation/storekit/transaction/finish()): "Call `finish()` to complete a transaction after you deliver the purchased content". For a tip, "delivery" is just showing a thank-you, so finish as soon as the transaction is verified.
- [`Transaction.unfinished`](https://developer.apple.com/documentation/storekit/transaction/unfinished): "A transaction is unfinished until you call `finish()`". This can be checked at any time as a safety net.
- Handle `.userCancelled` and `.pending` (Ask to Buy) results without showing errors.

Place the listener in the app delegate or `AppState` init, not in the popover's view. The popover's views come and go, while the listener must live as long as the app.

## 6. Local testing

- [Setting up StoreKit Testing in Xcode](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode): StoreKit Testing is "a local test environment for testing in-app purchases without requiring a connection to App Store servers". To set it up, choose File > New > File from Template > StoreKit Configuration File. Choose a local file, or a synced one (Xcode 14+) that pulls from App Store Connect and can't be edited. Activate it under Edit Scheme > Run > Options > StoreKit Configuration. Prices in the file are "a placeholder value that's not connected to price tiers". Data in the file is never uploaded to App Store Connect and never ships in App Store builds.
- [StoreKitTest](https://developer.apple.com/documentation/storekittest) / [`SKTestSession`](https://developer.apple.com/documentation/storekittest/sktestsession): automates the same environment in XCTest. The calls include `init(configurationFileNamed:)`, `buyProduct(productIdentifier:)`, `refundTransaction(identifier:)`, Ask to Buy approve and decline, `allTransactions()`, `clearTransactions()`, and `disableDialogs = true` to run without UI. "Run tests that reconfigure the environment serially, not concurrently". Every session shares one environment. macOS apps need Xcode 12+ on macOS 11+.
- Suggested split: keep tip state handling (product list, purchase result mapped to UI state, thank-you persistence) in a pure type with unit tests. Use `SKTestSession` for one or two integration tests covering a successful purchase, a cancellation, and a refund. Use sandbox or TestFlight for a final manual check of the real sheet from the popover.

## 7. Privacy label and privacy manifest impact

- **Privacy manifest.** The [required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) categories are file timestamp, system boot time, disk space, active keyboards, and user defaults. StoreKit isn't on the list, and the requirement as written applies to "iOS, iPadOS, tvOS, visionOS, or watchOS", not macOS. Adding StoreKit doesn't change Mewt's privacy manifest.
- **App Privacy label** ([App privacy details](https://developer.apple.com/app-store/app-privacy-details/)):
  - "'Collect' refers to transmitting data off the device in a way that allows you and/or your third-party partners to access it..."
  - Under Apple frameworks: "You are not responsible for disclosing data collected by Apple."
  - Payment Info: "If your app uses a payment service, the payment information is entered outside your app, and you as the developer never have access to the payment information, it is not collected and does not need to be disclosed."
  - Conclusion: as long as Mewt doesn't send purchase or transaction data to any server (and it has no server), it can keep **"Data Not Collected"**. That page doesn't mention StoreKit by name, so this is a reasoned reading of Apple's definitions. Sales reports in App Store Connect are Apple-collected data.
- **Sandbox network entitlement (UNVERIFIED).** Mewt currently lacks `com.apple.security.network.client`. StoreKit 2 runs its networking through system daemons, so it most likely works without that entitlement, but no Apple source states this. Test it in the prototype with the current entitlements, using sandbox or TestFlight rather than the local `.storekit` file, which never touches the network. If the entitlement does turn out to be required, it would conflict with the "no network" positioning and needs a decision.

## Open items / not verified

1. Apple's actual auto-generated THB equivalents for $0.99-$9.99. Read them in App Store Connect.
2. Purchase-sheet behaviour from a transient `NSPopover` in an `LSUIElement` app. Needs the UI prototype (mitigations A/B/C).
3. Whether StoreKit purchases work without `com.apple.security.network.client` in a sandboxed app. Test in sandbox or TestFlight.
4. The "donation" rejection risk is inferred from guideline structure, not stated by Apple.
5. That the Paid Apps Agreement also requires completed tax and banking information comes from third-party guides only.
