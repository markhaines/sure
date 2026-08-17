# Provider Integrations: Pending Transactions, FX and Debug Logging

Reference for the bank/aggregator provider layer. The short rules live in `AGENTS.md`.

The pending/FX facts below were reconciled against the code on 2026-08-17. The initializers
in `config/initializers/` are the source of truth; if this file and the code disagree, the
code wins and this file should be corrected.

## Pending detection

| Provider | Pending when | Stored at |
|---|---|---|
| SimpleFIN | provider sends `pending: true`, or `posted` is blank/0 and `transacted_at` is present | `extra["simplefin"]["pending"]` |
| Plaid (bank/credit) | Plaid sends `pending: true`, via `PlaidEntry::Processor` | `extra["plaid"]["pending"]` |
| Plaid (investments) | not supported: investment transactions do not store pending metadata | n/a |
| Lunchflow | API returns `isPending: true`, via `LunchflowEntry::Processor` | `extra["lunchflow"]["pending"]` |
| Manual / CSV import | no pending concept | n/a |

Lunchflow never returns real IDs for pending transactions, so the processor synthesises
`lunchflow_pending_<hash>` external IDs and reconciles them against the posted version when
it arrives. See `app/models/lunchflow_entry/processor.rb`.

## Storage

- Provider metadata lives on `Transaction#extra`, namespaced by provider key.
- SimpleFIN FX metadata: `extra["simplefin"]["fx_from"]`, `extra["simplefin"]["fx_date"]`.

## UI

- A small "Pending" badge renders when `transaction.pending?` is true.
- Providers that do not expose pendings simply show nothing.

## Configuration

Runtime toggles live in per-provider initializers and are read via `Rails.configuration.x.*`.

| Provider | Initializer | Default | Env override |
|---|---|---|---|
| SimpleFIN | `config/initializers/simplefin.rb` | pending **on** | `SIMPLEFIN_INCLUDE_PENDING=0` to disable |
| Plaid | `config/initializers/plaid_config.rb` | pending **on** | `PLAID_INCLUDE_PENDING=0` to disable |
| Lunchflow | `config/initializers/lunchflow.rb` | pending **off** | `LUNCHFLOW_INCLUDE_PENDING=1` to enable |

SimpleFIN and Plaid fetch pending transactions by default so they can be badged, excluded
from budgets (but counted in net worth), reconciled when the posted version arrives, and
auto-excluded after 8 days if they go stale.

There is also a self-hosted setting, `Setting.syncs_include_pending`, exposed in the hosting
settings UI. Its default is computed from the two env vars (`SIMPLEFIN_INCLUDE_PENDING` and
`PLAID_INCLUDE_PENDING`, both defaulting to `1`), and the UI toggle is disabled whenever
either env var is explicitly set. See `app/models/setting.rb`.

### Debug logging env vars

- `SIMPLEFIN_DEBUG_RAW=1`: log the raw payload returned by SimpleFIN.
- `LUNCHFLOW_DEBUG_RAW=1`: log the raw payload returned by the Lunchflow API.
- `UP_DEBUG_RAW=1`: log the raw payload returned by the Up API. Development only: the dump
  contains PII (merchant names, amounts, account IDs) and is gated to local environments, so
  it never fires in managed or production.

## Debug logging for provider syncs

When a provider sync or import path hits a recoverable error or a suspicious partial
response that support may need to inspect later, prefer `DebugLogEntry.capture(...)` over
`Rails.logger.*`.

- Record support-relevant diagnostics in the debug log so they surface in the
  super-admin-friendly `/settings/debug` UI, rather than leaving them only in raw
  application logs.
- Include `category`, `level`, `message`, `source`, `provider_key`, and useful structured
  `metadata`.
- Attach `family` and `account_provider` whenever available so support can filter and trace
  the affected connection.
- Reserve raw Rails logging for low-value local noise. Anything an operator may need should
  go to the debug log.

## Adding a new provider

For securities price providers (Tiingo, EODHD, Binance-style crypto), see
[adding-a-securities-provider.md](./adding-a-securities-provider.md): provider class,
registry wiring, MIC handling, settings UI, locales and tests.
