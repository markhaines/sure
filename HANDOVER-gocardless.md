# GoCardless provider for Sure — handover

**Status:** working end to end, deployed, parked 2026-08-16.
**Branch:** `feat/gocardless-provider` on `markhaines/sure` (fork of `we-promise/sure`), 15 commits, pushed, no PR opened.

This document is written for someone picking the work up cold. It covers what exists, why
the non-obvious decisions were made, and what is genuinely unfinished.

---

## 1. Why this exists

Mark wanted UK bank sync (NatWest) in Sure. Every route Sure ships is closed to UK users:

| Provider | UK verdict |
|---|---|
| Enable Banking | **EU/EEA only.** Their docs use `GB` as a country-code example, which is misleading: the live country list has no UK, and the UK left the EEA |
| Plaid | Docs state Production is not available to European users |
| SimpleFIN | US and Canada only |
| Brex / Mercury | US business banking |
| Wise | Wise accounts only |

GoCardless Bank Account Data covers the UK, but **closed to new customers around September
2025**. Mark has grandfathered access, which is the scarce asset the whole project rests
on. Sure had no GoCardless provider, hence this work.

Credentials are account-level: the `secret_id`/`secret_key` pair *is* the access. There is
no application to register and redirect URLs are passed per-requisition rather than
pre-whitelisted. The Bank Account Data portal (`bankaccountdata.gocardless.com`) is a
**separate login** from the `gocardless.com` merchant dashboard, which is a common
stumbling block.

## 2. What works

Verified against real NatWest data:

- Consent flow: pick bank → end user agreement → requisition → bank auth → callback
- 3 accounts imported (1 current, 2 credit cards), correctly typed and classified
- 648 transactions imported with correct signs
- Net worth computes correctly (−£12,088.17 against the real balances)
- Also built: **configurable transaction list columns**, including notes and tags
  (unrelated to GoCardless; Mark asked for it while testing)

Deployed to `sure.hainesy.com` (docker-main). Tests: 24 provider tests + 7 column tests,
all passing. Rubocop, erb_lint, zeitwerk and brakeman clean.

## 3. The three traps that will bite you

These are not theoretical. Each one shipped, looked fine, and was caught only by checking
real numbers.

### 3.1 The sign conventions are inverted in TWO directions

- **Transactions:** GoCardless reports a debit as NEGATIVE; Sure stores money-out as
  POSITIVE. So amounts are negated in
  `GocardlessAccount::Transactions::Processor#parse_transaction_amount`.
- **Balances:** Sure stores a liability as a POSITIVE amount owed; GoCardless reports a
  card you owe money on as NEGATIVE. So card balances are negated *again* in
  `GocardlessAccount#normalised_balance`.

That asymmetry is correct but deeply counter-intuitive. Getting the balance one wrong made
net worth read **+£18,759 instead of −£12,088**, a £30k error that still looks like a
plausible number. Negating, not `abs`: a card in credit should become a negative liability
rather than more debt. Both are covered by tests — do not "simplify" them.

### 3.2 Account types are ISO 20022, not Sure's vocabulary

GoCardless sends `cashAccountType` codes (`CACC`, `CARD`, `SVGS`, `LOAN`). Sure's
`infer_accountable_type` expects `"credit_card"` etc, so **everything fell through to the
Depository default** and both credit cards were created as cash accounts with their debt
counted as assets. Mapping lives in `GocardlessAccount::ISO20022_ACCOUNTABLE_TYPES`.

Note `Depository` is deliberately left WITHOUT a subtype. Its default is `"checking"`, but
`CACC` only means "cash account", so applying the default would relabel a plain current
account away from Sure's generic **Cash** category on an assumption the data does not
support. Cards do get `credit_card`, because `CARD` positively identifies one.

### 3.3 Rate limits are a normal operating condition

Account endpoints allow roughly **4 calls per account per day**. A 429 is "come back
tomorrow", not a failure. The importer counts it and **keeps the account in the upstream
list** so the pruner does not delete an account that is merely quota-blocked. Each account
costs 3 calls to import (metadata + details + balances) plus 1 for transactions, so a
single full sync of 3 accounts is already 12 calls.

## 4. Architecture

```
Provider::Gocardless             API client (token cache, institutions, agreements,
                                 requisitions, accounts/balances/transactions)
Provider::GocardlessAdapter      wires per-family credentials into the provider registry
GocardlessItem                   one bank connection; holds credentials + requisition state
GocardlessItem::Importer         requisition → account ids → details/balances/transactions
GocardlessAccount                account mapping, balance selection, ISO 20022 types
  ::Transactions::Processor      transaction mapping (signs, names, ids)
GocardlessItemsController        new (bank picker) → connect → callback → setup_accounts
```

Points worth knowing:

- **Trailing slashes are load-bearing** on the GoCardless API. `/api/v2/institutions/`
  works; without the slash it redirects, drops the Authorization header, and surfaces as a
  confusing 401. Every path in the client ends in a slash deliberately.
- **Access tokens are cached in `Rails.cache`** keyed by a SHA256 of the secret_id (never
  the credentials). Minting is itself rate-limited. A 401 triggers exactly one retry with a
  fresh token.
- **Balance selection is ordered**, preferring `interimAvailable` then `closingBooked`.
  Banks return several `balanceType` values; without ordering the figure shown depends on
  arbitrary array order and can silently disagree with the bank's own app.
- **The item is created at `connect`, not before.** Credentials are account-level so there
  is nothing meaningful to persist until a bank is chosen, and creating earlier would mean
  a GET request creating records.
- **The consent redirect validates its host** against trusted GoCardless domains before
  following (brakeman flagged the unguarded version).

## 5. Environments

### Dev
`~/code/sure-dev/dev.sh` drives a stack on docker-webapps (`/docker/sure-dev/`, port 3000,
own Postgres/Redis). Runtimes stay off the Mac by house rule.

```
./dev.sh server      # tailwind build + watcher + rails server
./dev.sh rails ...   # any rails command
./dev.sh run "..."   # arbitrary command in the container
./dev.sh css         # rebuild tailwind
```

Two hard-won details baked into that script:

- **`run` rsyncs the Mac over the container FIRST.** So a command that verifies files the
  container just generated silently checks the pre-generation state. Generate and verify in
  a SINGLE invocation. This produced a false "all clean" once.
- **A branch guard** refuses to sync when the local branch differs from what the container
  runs (`ALLOW_BRANCH_SWITCH=1` overrides). Added after switching branches for a code
  review swapped the provider out from under a live bank consent.

### Production
`sure.hainesy.com` on docker-main, `/docker/sure/`.

⚠️ **Runs `sure-gocardless:local`, built on that host from `/docker/sure-build`, NOT the
upstream image.** So `docker compose pull` and dockhand auto-update will not update it.

```bash
rsync -az --delete --exclude '.git/' --exclude 'node_modules/' --exclude 'tmp/' \
  --exclude 'log/' --exclude 'storage/' ~/code/sure/ root@192.168.10.36:/docker/sure-build/
ssh root@192.168.10.36 "cd /docker/sure-build && docker build -t sure-gocardless:local ."
ssh root@192.168.10.36 "cd /docker/sure && docker compose up -d --no-build web worker"
```

To revert to upstream, set both app images back to `ghcr.io/we-promise/sure:stable`. The
GoCardless tables remain; the provider disappears from the UI.

## 6. Unfinished / next steps

1. **No upstream PR for the provider.** The branch is a fork only. Upstream have an open
   request for European coverage ([discussion #366](https://github.com/we-promise/sure/discussions/366)),
   so this is genuinely wanted. Would need: a second reviewer on the sign conventions, a
   decision about the `Depository` subtype question, and probably VCR cassettes since there
   are no fixtures for the API.
2. **Pending transaction duplication is unproven.** Where a bank omits `transactionId` on
   pending entries, a deterministic surrogate is derived from date+amount+description; when
   the entry later posts with a real id it can appear twice until the pending copy ages
   out. **NatWest sends `transactionId` on pending entries, so this never triggered here.**
   Another bank will exercise it.
3. **Only one institution tested.** NatWest only, one country (GB). The country list in the
   picker is hard-coded to 15 countries.
4. **Abandoned consents accumulate.** Entering the bank picker and not completing leaves a
   `CR` requisition and an item behind. Two were cleaned up by hand during testing. Worth a
   sweep of stale `CR` items, or reusing an existing one per institution.
5. **No reauthorisation flow.** Consent expires after 90 days (NatWest's max). When it
   does, the item needs a fresh requisition. Enable Banking has a `reauthorize` action to
   model this on. **This will bite around mid-November 2026.**
6. **`setup_accounts` view was repaired by hand.** The generator emitted broken ERB (see
   below); the repaired views work but have not been reviewed as UI.

## 7. Upstream generator bugs

`rails g provider:family` is badly broken. Six bugs found, all by using it:

| Bug | Effect |
|---|---|
| Duplicate migration columns | `db:migrate` aborts |
| Source-enum patcher emits invalid Ruby | eager load fails in an unrelated file |
| Missing `scope :syncable` | breaks nightly family sync for **every** provider |
| Locale `%%{count}` | UI shows literal `%{count}` |
| Accounts-controller regex no longer matches | `/accounts` raises NoMethodError |
| View templates keep their ERB-escaping wrapper | generated views raise NameError |

The first four (plus trailing-comma and empty-hash edge cases found in review) are fixed in
**[we-promise/sure#3047](https://github.com/we-promise/sure/pull/3047)** — open, 6 commits,
all review threads resolved, awaiting a maintainer. Bugs 5 and 6 are fixed **locally only**
and still need upstreaming; 6 in particular needs care, since the fix is in the `.tt`
templates rather than the generated output.

Treat anything that generator produces as a draft.

## 8. Credentials and data

- GoCardless `secret_id`/`secret_key` live in Actual Budget's secrets table
  (`/docker/actualbudget/server-files/account.sqlite`, names `gocardless_secretId` /
  `gocardless_secretKey`) and are documented on the Anytype "Third-Party API Keys" page.
- **ActiveRecord encryption is OFF on both instances**, so provider credentials are stored
  in plaintext in the database. That is what made moving the dev database to prod possible.
  If encryption is ever enabled, credentials will need re-entering.
- Prod data is currently treated as test data by Mark.
