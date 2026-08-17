# Repository Guidelines

Single source of truth for coding agents in this repo. Claude Code loads it via the
`@AGENTS.md` import in `CLAUDE.md`; Codex and Gemini CLI read this file natively. Put project
rules here, not in a harness-specific file, so every agent reads the same instructions.

Deep reference material lives in `docs/llm-guides/` and is linked from the relevant section
below, so it loads on demand instead of on every session.

## Project Structure & Module Organization
- Code: `app/` (Rails MVC, services, jobs, mailers, components), JS in `app/javascript/`, styles/assets in `app/assets/` (Tailwind, images, fonts).
- Config: `config/`, environment examples in `.env.local.example` and `.env.test.example`.
- Data: `db/` (migrations, seeds), fixtures in `test/fixtures/`.
- Tests: `test/` mirroring `app/` (e.g., `test/models/*_test.rb`).
- Tooling: `bin/` (project scripts), `docs/` (guides), `public/` (static), `lib/` (shared libs).

## Build, Test, and Development Commands

### Setup and development server
- `cp .env.local.example .env.local && bin/setup`: install deps, set up DB, prepare app.
- `bin/dev`: start the development server (Rails, Sidekiq, Tailwind watcher) via `Procfile.dev`.
- `bin/rails server`: Rails server only.
- `bin/rails console`: Rails console.

### Testing
- `bin/rails test`: run all Minitest tests.
- `bin/rails test:db`: run tests with a database reset.
- `bin/rails test test/models/account_test.rb`: run a specific file.
- `bin/rails test test/models/account_test.rb:42`: run the test at a line.
- `DISABLE_PARALLELIZATION=true bin/rails test:system`: system tests only. Use sparingly, they are slow.

Inside the Dev Container, `SELENIUM_REMOTE_URL` is set automatically to the bundled
`selenium/standalone-chromium` service, so system tests use that remote browser and no local
Chrome is needed. To watch the browser live, open `http://localhost:7900` or
`http://localhost:4444` on the host (password: `secret`).

### Linting and formatting
- `bin/rubocop`: Ruby style checks. Add `-A` to auto-correct safe cops.
- `bundle exec erb_lint ./app/**/*.erb`: ERB linting (see `.erb_lint.yml`). Add `-a` to auto-correct.
- `npm run lint` / `npm run lint:fix` / `npm run format`: JS/TS via Biome.
- `bin/brakeman`: static security analysis.

### Database
- `bin/rails db:prepare`: create and migrate.
- `bin/rails db:migrate`: run pending migrations.
- `bin/rails db:rollback`: roll back the last migration.
- `bin/rails db:seed`: load seed data.

## Pre-Pull Request CI Workflow

ALWAYS run these before opening a pull request, and only open the PR if all pass:

1. **Tests** (required): `bin/rails test`, plus
   `DISABLE_PARALLELIZATION=true bin/rails test:system` when the change touches user flows.
2. **Linting** (required): `bin/rubocop -f github -a` and
   `bundle exec erb_lint ./app/**/*.erb -a`.
3. **Security** (required): `bin/brakeman --no-pager`.

## Agent Operating Rules

- Read the conventions below before generating any code.
- Use `Current.user` for the current user. Do NOT use `current_user`.
- Use `Current.family` for the current family. Do NOT use `current_family`.
- Do not run `rails server` as part of a response.
- Do not run `touch tmp/restart.txt`.
- Do not run `rails credentials`.
- Do not run migrations automatically.

## Architecture

### Application modes
- **Managed**: a team operates the servers (`Rails.application.config.app_mode = "managed"`).
- **Self Hosted**: users run it themselves, usually via Docker Compose (`app_mode = "self_hosted"`).

### Core domain model
- **User** has many **Accounts**, which have many **Transactions**.
- **Account** types: checking, savings, credit cards, investments, crypto, loans, properties.
- **Transaction** belongs to a **Category**, can have **Tags** and **Rules**.
- **Investment accounts** have **Holdings**, which track **Securities** via **Trades**.
- Multi-currency: values stored in the user's base currency, `Money` objects handle conversion
  and formatting, historical exchange rates back the reporting.

### API architecture
- Internal API: controllers serve JSON via Turbo for SPA-like interactions.
- External API: `/api/v1/` namespace, Doorkeeper OAuth plus API key authentication.
- Responses render through Jbuilder templates.
- Rate limiting via Rack Attack, configurable per API key.

### Sync and import
1. **Provider sync** (Plaid, SimpleFIN, Lunchflow, Up): `PlaidItem` and siblings manage
   connections, `Sync` tracks operations, background jobs apply updates.
2. **CSV import**: `Import` manages sessions, supports transaction and balance imports with
   custom field mapping and transformation rules.

Pending-transaction detection, FX metadata, provider env vars and the `DebugLogEntry` rules
are in [provider-integrations.md](./docs/llm-guides/provider-integrations.md). Read it before
touching any provider sync path.

### Background processing
Sidekiq handles async work: `SyncJob` (account syncing), `ImportJob`, `AssistantResponseJob`
(AI chat), and scheduled maintenance via sidekiq-cron.

### Frontend
- **Hotwire**: Turbo plus Stimulus, reactive UI without heavy JavaScript.
- **ViewComponents** in `app/components/`, Stimulus controllers organised alongside them.
- **Charts**: D3.js (time series, donut, sankey).
- **Styling**: Tailwind CSS v4.x with the design system in
  `app/assets/tailwind/sure-design-system.css`.
- Details, including the ViewComponent-vs-partial call, DS primitives, Stimulus patterns and
  i18n keys: [frontend-components.md](./docs/llm-guides/frontend-components.md).

### Security and authentication
- Session-based auth for web users.
- API auth via OAuth2 (Doorkeeper) for third-party apps, and API keys with JWT tokens for
  direct access.
- Scoped permissions for API access; strong parameters and CSRF protection throughout.

### Performance
- Proper indexes; prevent N+1 with `includes`/`joins`.
- Heavy work goes to background jobs; cache expensive calculations.
- Turbo Frames for partial page updates.

### Development workflow
Feature branches merge to `main`. Docker for consistent environments, env vars via `.env`
files, Lookbook for component development (`/lookbook`), Letter Opener for email previews.

## Project Conventions

1. **Minimize dependencies.** Push Rails to its limits first. A new dependency needs a strong
   technical or business reason. Favour old and reliable over new and flashy.
2. **Skinny controllers, fat models.** Put business logic in `app/models/`, using concerns and
   POROs for organisation. Models answer questions about themselves: `account.balance_series`,
   not `AccountSeries.new(account).call`. `app/services/` exists for historical reasons; do not
   add new business logic there.
3. **Hotwire-first frontend.** Native HTML over JS components (`<dialog>` for modals,
   `<details><summary>` for disclosures). Turbo frames over client-side solutions. Query params
   for state over localStorage/sessions. Server-side formatting for currencies, numbers, dates.
   Always use the `icon` helper from `application_helper.rb`, never `lucide_icon` directly.
4. **Optimize for simplicity.** Good OOP domain design beats micro-optimisation. Spend
   performance effort only on critical or global paths.
5. **Database vs ActiveRecord validations.** Simple validations (null checks, unique indexes)
   in the DB. ActiveRecord validations for form convenience, preferring client-side where
   possible. Complex validations and business logic in ActiveRecord.

## Coding Style & Naming Conventions
- Ruby: 2-space indent, `snake_case` for methods/vars, `CamelCase` for classes/modules. Follow Rails conventions for folders and file names.
- Views: ERB checked by `erb-lint` (see `.erb_lint.yml`). Avoid heavy logic in views; prefer helpers/components.
- JavaScript: `lowerCamelCase` for vars/functions, `PascalCase` for classes/components. Let Biome format code.
- All user-facing strings go through `t()`, and locale files are updated in the same change.
- Commit small, cohesive changes; keep diffs focused.

## Testing Guidelines

- **Always Minitest plus fixtures.** Never RSpec or factories in `test/`. The one exception is
  the docs-only rswag specs in `spec/`, covered under API Development below.
- Name files `*_test.rb`, mirroring the `app/` structure.
- Keep fixtures minimal, 2 to 3 per model for base cases; create edge cases inline in the test.
  Use Rails helpers when a test needs bulk fixture creation.
- Shared helpers live in `test/support/`. VCR cassettes back external HTTP.
- Write minimal, effective tests. Only cover critical paths that meaningfully raise confidence.
  System tests are for critical user flows only. Write tests as you go.
- **Test boundaries correctly.** Commands: assert they were called with the right params.
  Queries: assert the output. Do not test another class's implementation details, and do not
  test ActiveRecord itself.
- **Stubs and mocks:** use the `mocha` gem, prefer `OpenStruct` for mock instances, and mock
  only what is necessary.

```ruby
# GOOD - Testing critical domain business logic
test "syncs balances" do
  Holding::Syncer.any_instance.expects(:sync_holdings).returns([]).once
  assert_difference "@account.balances.count", 2 do
    Balance::Syncer.new(@account, strategy: :forward).sync_balances
  end
end

# BAD - Testing ActiveRecord functionality
test "saves balance" do
  balance_record = Balance.new(balance: 100, currency: "USD")
  assert balance_record.save
end
```

## API Development Guidelines

Touching `app/controllers/api/v1/` is gated by three MANDATORY rules:

1. Every endpoint has a matching rswag request spec in `spec/requests/api/v1/`, for
   **documentation only**, regenerating `docs/api/openapi.yaml`.
2. Behavioral coverage lives in Minitest at
   `test/controllers/api/v1/{resource}_controller_test.rb`, never in rswag.
3. Every rswag spec uses the same `X-Api-Key` auth pattern, never Doorkeeper/OAuth.

Read [api-endpoints.md](./docs/llm-guides/api-endpoints.md) before starting: it carries the
spec template, the regeneration command, the full post-commit checklist (issue #944) and the
`verify_api_endpoint_consistency.rb` verification commands.

## Design System Hygiene (UI PRs)

When a PR touches `.erb`, view components, or `.css`:

1. **Tokens, not palette.** Use functional tokens from `app/assets/tailwind/sure-design-system.css` (`bg-warning/10`, `text-destructive`, `bg-container`, `text-primary`, `border-primary`). No raw Tailwind palette (`bg-blue-50`, `text-red-500`, hex literals).
2. **Reach for `DS::*` first.** Check `app/components/DS/` (`DS::Alert`, `DS::Button`, `DS::Disclosure`, `DS::Dialog`, `DS::Menu`, etc.) before writing an alert, badge, button, disclosure, dialog, or input shape.
3. **Two copies → lift to DS.** Same hand-rolled shape ≥2× in a diff with no DS equivalent → propose a new `DS::*` primitive before the second copy lands.
4. **Conventions.** Use the `icon` helper (never `lucide_icon` directly), no raw SVG outside DS primitives, user-facing strings via `t()`, avoid arbitrary `*-[Npx]` values when a scale token fits.
5. **Never add new styles** to the design system files without permission.

Reviewers escalate violations of (2)–(3) to close/rewrite; the rest are request-changes.

## Commit & Pull Request Guidelines
- Commits: Imperative subject ≤ 72 chars (e.g., "Add account balance validation"). Include rationale in body and reference issues (`#123`).
- PRs: Clear description, linked issues, screenshots for UI changes, and migration notes if applicable. Ensure CI passes, tests added/updated, and `rubocop`/Biome are clean.

## Security & Configuration Tips
- Never commit secrets. Start from `.env.local.example`; use `.env.local` for development only.
- Run `bin/brakeman` before major PRs. Prefer environment variables over hard-coded values.

## Further Guides

All in `docs/llm-guides/`, read on demand: `provider-integrations.md` (pending, FX, debug
logging), `frontend-components.md` (components, Stimulus, i18n), `api-endpoints.md` (rswag,
consistency checklist), `adding-a-securities-provider.md`, `gating-a-preview-feature.md`,
`goals.md`, `wealth-blueprint.md`, `wealth-agent-harness.md`.
