# Frontend: Components, Stimulus and i18n

Detailed reference for view work. The short rules live in `AGENTS.md`; this file holds the
decision criteria and worked examples so they do not load into every session.

## ViewComponent vs partial

**Use a ViewComponent when the element:**
- has complex logic or styling patterns
- will be reused across multiple views or contexts
- needs structured styling with variants/sizes
- requires interactive behaviour or a Stimulus controller
- has configurable slots or a non-trivial API
- needs accessibility features or ARIA support

**Use a partial when the element:**
- is primarily static HTML with minimal logic
- is used in only one or a few specific contexts
- is simple template content
- needs no variants, sizes or configuration
- is about content organisation rather than reusable functionality

**Either way:**
- Prefer a component over a partial when one already exists.
- Keep domain logic OUT of view templates. Logic belongs in the component file.

## Design system

The enforced rules (functional tokens over raw palette, `DS::*` first, lift to DS on the
second copy, the `icon` helper, no new design-system styles without permission) are in the
"Design System Hygiene" section of `AGENTS.md`. They are deliberately not repeated here, so
there is only one copy to keep current. Token and primitive definitions themselves live in
`app/assets/tailwind/sure-design-system.css`.

## Stimulus controllers

Declarative actions are required. The HTML declares what happens:

```erb
<!-- GOOD: Declarative - HTML declares what happens -->
<div data-controller="toggle">
  <button data-action="click->toggle#toggle" data-toggle-target="button">
    <%= t("components.transaction_details.show_details") %>
  </button>
  <div data-toggle-target="content" class="hidden">
    <p><%= t("components.transaction_details.amount_label") %>: <%= @transaction.amount %></p>
    <p><%= t("components.transaction_details.date_label") %>: <%= @transaction.date %></p>
    <p><%= t("components.transaction_details.category_label") %>: <%= @transaction.category.name %></p>
  </div>
</div>
```

**Controller best practices:**
- Keep controllers lightweight and simple (fewer than 7 targets).
- Use private methods and expose a clear public API.
- Single responsibility, or highly related responsibilities.
- Component controllers stay in the component directory; global controllers live in
  `app/javascript/controllers/`.
- Pass data via `data-*-value` attributes, not inline JavaScript.

## Internationalisation

Every user-facing string goes through `t()`. Update locale files in the same change.

- **Key organisation**: hierarchical, by feature or component:
  `accounts.index.title`, `transactions.form.amount_label`,
  `components.transaction_details.show_details`.
- **Descriptive names**: `show_details`, not `button`.
- **Grouping**: keep related translations in the same namespace.
- **Interpolation**: `t("users.greeting", name: user.name)`.
- **Pluralisation**: `t("transactions.count", count: @transactions.count)`.
- **Locale files**: add new strings to `config/locales/en.yml`.
- **Missing translations**: configured to raise in development.

Example locale structure for the Stimulus example above:

```yaml
en:
  components:
    transaction_details:
      show_details: "Show Details"
      hide_details: "Hide Details"
      amount_label: "Amount"
      date_label: "Date"
      category_label: "Category"
```
