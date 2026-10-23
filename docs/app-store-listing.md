# App Store listing — Billow 1.0.0

Source of truth for the App Store Connect metadata (filled via the API; edit
there or here and re-run).

## App information

- **Name:** Billow: Card Spend Tracker
- **Subtitle:** Every card. Every charge.
- **Primary category:** Finance
- **Privacy policy URL:** https://billow-app.pages.dev/privacy
- **Age rating:** 4+ (no objectionable content; no ads, chat, user-generated content, web browsing or gambling)

## Version 1.0.0

- **Support URL:** https://billow-app.pages.dev/
- **Marketing URL:** https://billow-app.pages.dev/
- **Copyright:** 2026 Houchen Li
- **Release:** manually, after approval

### Promotional text

Every purchase on every credit card, tracked automatically. No Billow account, no servers, no subscription — your spending data stays on your iPhone.

### Keywords

expense,spending,budget,credit card,tracker,money,bills,transactions,categories,finance,cards,daily

### Description

Billow keeps a running tally of what you spend across all of your credit cards — automatically.

Connect your banks once and every swipe, tap, online order and subscription shows up on its own, sorted into categories, with a daily chart and a month-to-date total that tells you whether you're on pace.

REQUIRES: a US bank or card issuer and your own free Plaid account (the in-app guide walks you through setup).

PRIVATE BY DESIGN
• No Billow account and no Billow servers. Your transactions are stored only on your iPhone.
• You connect banks through your own free Plaid account (Plaid's Trial plan covers 10 bank logins). Your keys stay in the iOS Keychain and are sent only to Plaid.
• No ads, no tracking, no analytics.

WHAT YOU GET
• This month's spending at a glance, your pace for the month, and how it compares with last month
• A 30-day spending chart — tap any day to see its total
• Automatic categories — dining, groceries, shopping, transport, travel and more — that learn from your edits
• Per-card totals and a searchable activity list with notes
• Notifications for new charges
• Optional instant logging of in-store Apple Pay taps through a Shortcuts automation — handy for Apple Card

SETUP TAKES ABOUT 10 MINUTES
1. Create a free account at dashboard.plaid.com and apply for the Trial plan.
2. Add Billow's redirect address in the Plaid dashboard.
3. Paste your Plaid keys into Billow and link your banks.
The in-app guide walks you through each step. Want to look around first? Turn on demo data.

Billow is a read-only spending tracker: it can't move money, make payments or change anything at your bank. Bank connections are provided by Plaid under your own Plaid account.

## App Review notes

Billow is a read-only personal spending tracker. It has no backend server and no user accounts; all data is stored on the device.

TO EXPLORE WITHOUT A BANK: on first launch tap "Explore with demo data" (or Accounts > Settings > Demo data).

TO TEST BANK LINKING (Plaid Sandbox, fake data):
1. Accounts > Set up bank sync (free).
2. Environment: Sandbox. client_id: [PASTE CLIENT_ID]   Sandbox secret: [PASTE SANDBOX SECRET]. Tap "Verify & save".
3. Accounts > Link a bank > search "First Platypus Bank" > username user_good, password pass_good.
Transactions appear on the Overview tab within about a minute.

ABOUT GUIDELINE 5.1.1(ix): Billow does not provide banking or financial services. It cannot move money, make payments or open accounts. It only displays the user's own transactions, retrieved through the user's own Plaid developer account and stored only on the device. The developer operates no servers and receives no user data.

The optional "Log Card Tap" App Intent records in-store Apple Pay taps via a Shortcuts "Transaction" automation that the user creates; it needs no extra permissions.
