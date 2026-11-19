# Support Mewt & Feedback Design Spec

- **Date:** 2026-10-19 (finalized 2026-11-11 post-sandbox verification)
- **Map:** [#2 Wayfinder: Support Mewt (tips) + Report a Bug for 1.0](https://github.com/chaninlaw/Mewt/issues/2)
- **Status:** Approved for 1.0 implementation

---

## 1. Goal

Provide a voluntary, non-intrusive tipping mechanism ("Support Mewt") and an actionable, privacy-respecting bug reporting flow ("Report a Bug") in Mewt 1.0 before resuming App Store pre-submission:

1. **Support Mewt:** One-time StoreKit 2 consumable tips that unlock nothing and keep every feature 100% free.
2. **Report a Bug:** Direct email draft (`mailto:`) and public GitHub Issues submission with sanitized hardware and software diagnostic info prefilled, with zero automatic data transmission.
3. **Zero Network Constraint:** Maintain Mewt's core privacy promise ("Data Not Collected", 0 telemetry, 0 analytics, and no `com.apple.security.network.client` entitlement).

---

## 2. Non-Goals & Out of Scope

- **Subscriptions / Recurring Support:** No auto-renewable "Continuous Support" in 1.0. Keeps operational and customer support surface small.
- **External Payment Links:** No Buy Me a Coffee, Ko-fi, PromptPay, or Stripe links in the app (violates App Store Review Guideline 3.1.1).
- **Gated Features or Perks:** Tips unlock no functional features; Plus and Studio tiers remain deferred to later phases.
- **Supporter Badges or Stored State:** No persistent "Supporter" badge, state flags, or receipt storage in 1.0. Purchases are repeatable and stateless. (Note: on-device recognition remains retroactively possible in future versions via `SKIncludeConsumableInAppPurchaseHistory` in Info.plist + `Transaction.all`).
- **Automated Telemetry or Log Export:** No automatic transmission of crash reports, and no log dumping / `os_log` extraction in 1.0 due to App Sandbox restrictions and privacy posture.

---

## 3. Product Catalog & StoreKit 2 Lineup

### 3.1 Consumables under App Store Review Guideline 3.1.1

Under Guideline 3.1.1, developer tipping must use in-app purchases. Consumable IAPs are used because tips are repeatable, can be bought again at any time, require no "Restore Purchases" button, do not appear in `Transaction.currentEntitlements`, and do not require Family Sharing handling.

Wording must strictly use **"Tip"** or **"Support Mewt"**. The word **"Donate"** must not appear anywhere in the UI or metadata (Guideline 3.2.2(iv) restricts donations to recognized non-profit organizations).

### 3.2 Product Lineup & Pricing

Pricing uses Thailand (THB) as the base storefront. App Store Connect generates equivalent pricing for the other 174 storefronts. The app formats prices dynamically via `Product.displayPrice` and never hardcodes currency values.

| Display Name | Product Identifier | Base Price (TH Storefront) | ASC en-US Description |
|---|---|---|---|
| **Treat** | `com.chaninlaw.Mewt.tip.treat` | ฿35 (~$0.99) | A small tip for Mewt's developer |
| **Tuna Can** | `com.chaninlaw.Mewt.tip.tuna` | ฿99 (~$2.99) | A medium tip for Mewt's developer |
| **Cat Tower** | `com.chaninlaw.Mewt.tip.tower` | ฿349 (~$9.99) | A generous tip for Mewt's developer |

### 3.3 App Store Connect Submission Rules

- The first consumable IAP in an app cannot be submitted in isolation; it must be submitted alongside a new app version in the same App Store submission draft.
- Required metadata per product:
  - Reference name (e.g. `Tip Treat`, `Tip Tuna Can`, `Tip Cat Tower`)
  - Product ID (permanent, `com.chaninlaw.Mewt.tip.*`)
  - Display Name (2–30 characters, en-US)
  - Description (up to 45 characters, en-US, must contain "Tip")
  - Review screenshot (Mac 16:10, 2880×1800, no alpha)

---

## 4. UI & Presentation

### 4.1 Navigation & Placement

Following the prototype investigation ([#5](https://github.com/chaninlaw/Mewt/issues/5)), Layout B (dedicated sub-page) was selected:

1. **Support Mewt Entry Point:** A heart icon (`Image(systemName: "heart")`) placed in the main popover footer between **Settings…** and **Quit**, with accessibility help text `.help("Support Mewt")`.
2. **Support Mewt Sub-Page:**
   - Standard "‹ Back" navigation matching the Settings page.
   - Header text: *"Mewt is free and stays free. If you enjoy having Mewt on your menu bar, you can support its development with a tip."*
   - Three tip cards laid out horizontally side-by-side (Treat / Tuna Can / Cat Tower), showing a cat-themed icon/emoji, product name, and `product.displayPrice`.
   - Direct purchase: Clicking a card immediately triggers purchase confirmation with StoreKit; no intermediary confirm dialog.
   - Sub-caption: *"Tips are one-time and unlock nothing."*
3. **Report a Bug Entry Point:** Placed at the bottom of the existing **Settings** page:
   - Dedicated section labeled **Report a Bug**.
   - Two buttons: `Email…` and `GitHub Issues…` (marked with `(public)`).
   - Caption: *"Opens a draft in your email app or a GitHub page in your browser. Nothing is sent until you choose to send it. Address: chanin.lor@gmail.com"* (selectable text).

```
Main Popover Footer:
[ Settings… ]                [ ♥ ]  [ Quit ]
                               │
                               ▼
┌──────────────────────────────────────────────┐
│ ‹ Back       Support Mewt                    │
│                                              │
│ Mewt is free and stays free. If you enjoy    │
│ having Mewt on your menu bar, you can        │
│ support its development with a tip.          │
│                                              │
│ ┌──────────┐  ┌──────────┐  ┌──────────┐     │
│ │  🐟      │  │  🥫      │  │  🏰      │     │
│ │ Treat    │  │ Tuna Can │  │Cat Tower │     │
│ │ ฿35      │  │ ฿99      │  │ ฿349     │     │
│ └──────────┘  └──────────┘  └──────────┘     │
│                                              │
│ Tips are one-time and unlock nothing.        │
│                                              │
│ [ Thank you for supporting Mewt! ❤️ ]        │
└──────────────────────────────────────────────┘
```

### 4.2 Popover Window Pinning during Purchase

Mewt runs as an `LSUIElement` accessory app using a transient `NSPopover` (`behavior = .transient`). When StoreKit presents the system purchase sheet or Apple Account authentication modal, focus transfer normally causes transient popovers to close.

**The Fix (tested & verified in prototype #5):**
1. Before invoking `product.purchase(confirmIn: popoverWindow)`, switch `popover.behavior` to `.applicationDefined`.
2. Pass the popover's hosting window as `confirmIn: popoverWindow`.
3. In a `defer` block, restore `popover.behavior = .transient`.
4. The system sheet attaches directly to the popover window, the popover remains open, and the thank-you state renders properly upon completion.

### 4.3 UI States & Feedback

- **Loading:** Skeleton/disabled state while products load asynchronously via `Product.products(for:)`.
- **Load Error / Empty:** Replace cards with a quiet message: *"Tips are unavailable right now."* No auto-retry loop; reloads on next popover open.
- **Purchase Success:**
  - In-app text: *"Thank you for supporting Mewt! ❤️"* appears below cards.
  - Mascot reaction: Temporary celebratory reaction (~2–3 seconds) using existing mascot animation frames (`idle`/`talking` assets).
  - Stateless: After 3 seconds, mascot returns to normal state. Cards remain ready for another tip.
- **User Cancelled (`.userCancelled`):** Handled silently. No error banner or alert.
- **Pending (`.pending`):** Displays note *"Waiting for approval…"*. If approved later via `Transaction.updates`, triggers the celebratory thank-you.

---

## 5. Technical Architecture & State Management

### 5.1 Protocol-Driven StoreKit Manager

To preserve testability and avoid coupling SwiftUI views directly to StoreKit, an injectable protocol is introduced:

```swift
@MainActor
public protocol TipStoreControlling: AnyObject {
    var products: [Product] { get }
    var phase: TipStorePhase { get }
    var showsThankYou: Bool { get }
    
    func loadProducts() async
    func purchase(_ product: Product, in window: NSWindow?) async
    func startUpdatesListener()
}

public enum TipStorePhase: Equatable {
    case idle
    case loading
    case ready
    case purchasing(String)
    case pending
    case failed(String)
}
```

### 5.2 Transaction Lifecycle & App Launch Listener

Per Apple recommendations, `Transaction.updates` must be observed throughout the application lifetime to catch background approvals (Ask to Buy) and unfinished transactions:

```swift
@MainActor
@Observable
public final class TipStore: TipStoreControlling {
    public static let productIDs: [String] = [
        "com.chaninlaw.Mewt.tip.treat",
        "com.chaninlaw.Mewt.tip.tuna",
        "com.chaninlaw.Mewt.tip.tower"
    ]
    
    private var updatesTask: Task<Void, Never>?
    
    public func startUpdatesListener() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                self?.handlePurchased(transaction.productID)
            }
        }
    }
    
    public func purchase(_ product: Product, in window: NSWindow?) async {
        guard let window else { return }
        // Pin popover behavior
        TrayController.shared.pinPopoverForModal(true)
        defer { TrayController.shared.pinPopoverForModal(false) }
        
        do {
            let result = try await product.purchase(confirmIn: window)
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    handlePurchased(product.id)
                }
            case .userCancelled:
                break
            case .pending:
                self.phase = .pending
            @unknown default:
                break
            }
        } catch {
            self.phase = .failed(error.localizedDescription)
        }
    }
}
```

The listener is initialized in `AppState` or app launch lifecycle, **not** inside popover view bodies.

---

## 6. Report a Bug & Privacy Design

### 6.1 Diagnostic Data Payload

To assist in debugging while strictly guarding user privacy ([#6](https://github.com/chaninlaw/Mewt/issues/6)), the bug reporting mechanism gathers only non-identifying runtime metrics:

**Included:**
1. **App Version & Build:** e.g. `1.0 (1)`
2. **macOS Version & Build:** e.g. `macOS 15.1 (24B83)`
3. **Mac Hardware Model:** Model identifier from `sysctl hw.model` (e.g. `Mac15,3`), not user-assigned computer name.
4. **Mic Route Kind:** `Wired`, `Bluetooth`, or `None` (from `MicMuteController`).
5. **Mic Permission Status:** `Authorized`, `Denied`, or `Not Determined`.

**Explicitly Excluded:**
- User-assigned Bluetooth/mic device names (frequently contains owner name like "John's AirPods").
- Current mute state (misleading because it reflects state at report time, not bug time).
- Log export or process telemetry.

### 6.2 Email (`mailto:`) Integration

- **Recipient:** `chanin.lor@gmail.com`
- **Subject:** `Mewt <version> (<build>) — Bug report`
- **Body Construction:**
  ```text
  What happened:
  [Describe what went wrong]

  Steps to reproduce:
  1. 
  2. 
  3. 

  --- Diagnostics (feel free to edit or remove) ---
  App: Mewt 1.0 (1)
  macOS: 15.1 (24B83)
  Model: Mac15,3
  Input Route: Wired
  Mic Permission: Authorized
  ```
- **Fallback for missing default mail client:** The email address `chanin.lor@gmail.com` is displayed as copyable plain text directly in the UI caption.

### 6.3 GitHub Issue Template

For users preferring public tracking:
- URL queries open `.github/ISSUE_TEMPLATE/bug_report.yml` prefilled with the identical diagnostics markdown block.
- URL is opened via `NSWorkspace.shared.open(...)`.
- `config.yml` disables blank issues and links back to the support email.

---

## 7. Sandbox Verification & Entitlements

### 7.1 Zero Network Entitlement

As verified on 2026-11-11 in [#8](https://github.com/chaninlaw/Mewt/issues/8):
- StoreKit 2 transactions and product fetching operate entirely through the macOS system daemon `storekitagent`.
- **`com.apple.security.network.client` is NOT required.**
- Console logs during live sandbox purchases confirmed 0 `deny(1) network-outbound` violations for `Mewt Mic`.
- Mewt maintains its full offline posture and "Data Not Collected" App Privacy label.

### 7.2 Testing Strategy

1. **Unit Testing:**
   - Use `MockTipStore: TipStoreControlling` in test suites (`MewtTests`) to test view state, transitions, loading failures, and UI reactions without hitting system daemons.
2. **Local StoreKit Configuration (`Tips.storekit`):**
   - Add a Xcode StoreKit configuration file containing the 3 consumable products to test purchases locally without network access.
   - Integration tests using `StoreKitTest` (`SKTestSession`):
     - `init(configurationFileNamed: "Tips")`
     - `session.disableDialogs = true`
     - Test purchase verification and unfinished transaction cleanup.
3. **App Store Sandbox Testing Gotchas (from #8):**
   - **Configuration Reset:** An active `.storekit` scheme option persists with `storekitagent` per bundle ID. To test real Apple Sandbox, run from Xcode with **StoreKit Configuration = None**.
   - **Account Setup:** Do not use the primary Apple Account in System Settings > App Store > Sandbox Account; use a dedicated Sandbox Tester account with *Interrupt Purchases* set to **Off** to avoid `AMSErrorDomain 305`.

---

## 8. Pre-Submission & Documentation Updates

1. **`site/privacy.html`:**
   - Retain "Data Not Collected".
   - Under Third-Party Services / Payments, add clarification:
     > *"In-App Purchases (tips) are handled directly by Apple's App Store. Mewt does not receive or store any payment information, billing details, or personal data."*
2. **`tasks/pre-submission.md`:**
   - Update 1.0 Scope checklist: 1.0 includes voluntary tipping and bug reporting.
   - App Review Notes to include:
     > *"Support Mewt includes 3 optional consumable in-app purchases (tips) under guideline 3.1.1. Tips unlock no functionality or digital content; all features of the app remain 100% free. The app makes no direct network calls and does not require the outgoing network entitlement."*
3. **`tasks/app-store-listing.md`:**
   - Ensure app description text does not promise paid tier features or describe tips as "donations".
