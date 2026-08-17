# API Endpoints: OpenAPI Specs and Consistency Rules

Read this before adding or modifying anything in `app/controllers/api/v1/`. The one-line
summary of the mandatory rules is in `AGENTS.md`; this file holds the detail.

## OpenAPI documentation (MANDATORY)

Every endpoint needs a matching rswag request spec, for **DOCUMENTATION ONLY**. It exists to
generate the OpenAPI file, not to assert behaviour.

1. **Location**: `spec/requests/api/v1/{resource}_spec.rb`
2. **Framework**: RSpec with rswag for OpenAPI generation
3. **Schemas**: define reusable schemas in `spec/swagger_helper.rb`
4. **Generated docs**: `docs/api/openapi.yaml`

Example structure for a new endpoint:

```ruby
# spec/requests/api/v1/widgets_spec.rb
require 'swagger_helper'

RSpec.describe 'API V1 Widgets', type: :request do
  path '/api/v1/widgets' do
    get 'List widgets' do
      tags 'Widgets'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'

      response '200', 'widgets listed' do
        schema '$ref' => '#/components/schemas/WidgetCollection'
        run_test!
      end
    end
  end
end
```

Regenerate the docs after any change:

```bash
RAILS_ENV=test bundle exec rake rswag:specs:swaggerize
```

## Post-commit API consistency (issue #944)

After every API endpoint commit, ensure all three hold:

1. **Minitest behavioral coverage.** Add or update
   `test/controllers/api/v1/{resource}_controller_test.rb`. Use an API key and `api_headers`
   (`X-Api-Key`). Cover index/show, CRUD where relevant, and 401/403/422/404. Do not rely on
   rswag for behavioral assertions.
2. **rswag stays docs-only.** No `expect(...)` or `assert_*` in `spec/requests/api/v1/`. Use
   `run_test!` only, so the specs document request/response shapes and regenerate
   `docs/api/openapi.yaml`.
3. **One auth pattern in rswag.** Every request spec in `spec/requests/api/v1/` uses the same
   API key pattern: `ApiKey.generate_secure_key`, `ApiKey.create!(...)`,
   `let(:'X-Api-Key') { api_key.plain_key }`. Do not use Doorkeeper/OAuth in those specs, so
   the generated docs stay consistent.

Full checklist and pattern:
[.cursor/rules/api-endpoint-consistency.mdc](../../.cursor/rules/api-endpoint-consistency.mdc).

## Verification

```bash
ruby test/support/verify_api_endpoint_consistency.rb              # verify the implementation
ruby test/support/verify_api_endpoint_consistency.rb --compliance # scan current APIs for violations
```

## Related architecture

- Internal API: controllers serve JSON via Turbo.
- External API: `/api/v1/`, Doorkeeper OAuth plus API key authentication.
- Responses render through Jbuilder templates.
- Rate limiting via Rack Attack, configurable per API key.
