# Support Mewt + Report a Bug — Manual Test

Two passes. Pass A uses the local `Tips.storekit` (no Apple account, no real money). Pass B uses the real App Store Sandbox and needs all 3 tips created in App Store Connect first (`tasks/app-store-connect-tips.md`).

Quit any other copy of Mewt Mic first. Two copies would fight over the mic.

---

## Pass A — Local StoreKit (Debug)

**Run:** open `Mewt.xcodeproj` → scheme **Mewt Local Tips** → ⌘R.
**Optional, to watch logs:** Console.app with filter `subsystem:com.chaninlaw.Mewt`.

### Support page
- [ ] Main popover footer shows `Settings… · ♥ · Quit`. Hovering the heart shows "Support Mewt"
- [ ] Click the heart → page slides in with "‹" back button and the title "Support Mewt"
- [ ] Copy reads "Mewt is free and stays free…", with "Tips are one-time and unlock nothing." below
- [ ] 3 cards in order 🐟 Treat · 🥫 Tuna Can · 🏰 Cat Tower, with prices ฿35 / ฿99 / ฿349
- [ ] Click **Treat** → system purchase sheet attaches to the popover and **the popover stays open**
- [ ] Confirm → "Thank you for supporting Mewt! ❤️" appears, and a small mascot plays for ~3 s, then disappears while the text stays
- [ ] Click **Treat** again → it can be bought again (consumable, no "already purchased")
- [ ] Click **Tuna Can** → cancel the sheet → nothing happens, no error. Popover still open
- [ ] While a sheet is up, the other cards are greyed out
- [ ] ‹ Back, then reopen Support → the thank-you line is gone (fresh visit)
- [ ] Esc on the Support page goes back
- [ ] Click outside the popover after purchasing → popover closes normally (pin released)

### Edge states (Xcode → Debug → StoreKit → Manage Transactions / the `.storekit` editor)
- [ ] Editor → **Enable Ask to Buy** → buy Tower → "Waiting for approval…". Approve it in Manage Transactions → thank-you appears
- [ ] Editor → **Fail Transactions** (or a StoreKit error for `Purchase`) → buy → "The purchase didn't go through. Please try again."
- [ ] Editor → StoreKit error for `Load Products` → quit, relaunch, open Support → "Tips are unavailable right now." Turn it off, leave the page, come back → cards load (retries)

### Report a Bug (Settings page bottom)
- [ ] Section "Report a Bug" with **Email…** and **GitHub Issues… (public)**
- [ ] Caption ends with `chanin.lor@gmail.com`, and that text can be selected and copied
- [ ] **Email…** → Mail opens a draft to `chanin.lor@gmail.com`, subject `Mewt 1.0 (1) — Bug report`, body has "What happened / Steps" + a 5-line Diagnostics block
- [ ] Diagnostics show App, macOS (with build in parentheses), Model like `Mac15,3`, Input Route `Wired`/`Bluetooth`/`None`, Mic Permission
- [ ] With AirPods as input → Input Route says `Bluetooth` and **no AirPods name** appears anywhere
- [ ] **GitHub Issues…** → browser opens `github.com/chaninlaw/Mewt/issues/new?template=bug_report.yml…`. The Diagnostics box is prefilled **only after the PR is merged** (template must be on `main`). Before then GitHub shows a blank page

---

## Pass B — App Store Sandbox (real purchase flow)

Needs: all 3 IAPs exist in ASC (status *Ready to Submit* is enough), plus a Sandbox Tester (ASC → Users and Access → Sandbox → Test Accounts) with *Interrupt Purchases* **Off**. On the Mac: System Settings → App Store → **Sandbox Account** → sign in with the tester. **Don't** use your real Apple Account there.

**Run:** scheme **Mewt** (no StoreKit config) → ⌘R. Or the `/Applications` build, which is development-signed and so also talks to Sandbox.

- [ ] Support page shows 3 cards with Sandbox prices (THB)
- [ ] Buy each tip once → Apple sign-in / confirm sheet attaches to the popover and the popover stays open → thank-you
- [ ] Console filter `deny(1) network-outbound` while buying → **0 lines** for `Mewt Mic`
- [ ] Quit and relaunch, with Console filtered to `subsystem:com.chaninlaw.Mewt category:TipStore` → **no** `Tip delivered via updates` line. A line there means a transaction wasn't finished. The listener finishes it, so the worst case is one stale thank-you, but tell Claude
- [ ] Take the **review screenshot** for ASC now: Support page with the 3 cards (see guide step 3)

When both passes are green, tick the two "by hand" sub-items and the Sandbox item in `tasks/pre-submission.md` §8.
