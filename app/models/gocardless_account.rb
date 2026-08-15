# frozen_string_literal: true

class GocardlessAccount < ApplicationRecord
  include CurrencyNormalizable
  include GocardlessAccount::DataHelpers

  belongs_to :gocardless_item

  # Association through account_providers
  has_one :account_provider, as: :provider, dependent: :destroy
  has_one :account, through: :account_provider, source: :account
  has_one :linked_account, through: :account_provider, source: :account

  validates :name, :currency, presence: true

  # Scopes
  scope :with_linked, -> { joins(:account_provider) }
  scope :without_linked, -> { left_joins(:account_provider).where(account_providers: { id: nil }) }
  scope :ordered, -> { order(created_at: :desc) }

  # Callbacks
  after_destroy :enqueue_connection_cleanup

  # Helper to get account using account_providers system
  def current_account
    account
  end

  # Idempotently create or update AccountProvider link
  # CRITICAL: After creation, reload association to avoid stale nil
  def ensure_account_provider!(linked_account)
    return nil unless linked_account

    provider = account_provider || build_account_provider
    provider.account = linked_account
    provider.save!

    # Reload to clear cached nil value
    reload_account_provider
    account_provider
  end

  def upsert_from_gocardless!(account_data)
    # Convert SDK object to hash if needed
    data = sdk_object_to_hash(account_data).with_indifferent_access

    details = (data[:details] || {}).with_indifferent_access
    balances = Array(data[:balances])

    update!(
      gocardless_account_id: data[:id].to_s,
      # Banks rarely set a friendly `name`. Fall back through the fields most likely to
      # carry something a human recognises before resorting to the IBAN, so accounts do
      # not all show up as blank in the picker.
      name: details[:name].presence ||
            details[:displayName].presence ||
            details[:product].presence ||
            details[:ownerName].presence ||
            data[:owner_name].presence ||
            details[:iban].presence ||
            data[:iban].presence,
      current_balance: extract_balance(balances),
      # PSD2 always reports a currency per account; only fall back if the bank omits it.
      currency: details[:currency].presence || balances.first&.dig(:balanceAmount, :currency) || "GBP",
      account_status: data[:status] || details[:status],
      # cashAccountType follows ISO 20022: CACC current, SVGS savings, CARD card.
      account_type: details[:cashAccountType] || details[:product],
      provider: "gocardless",
      institution_metadata: extract_institution_metadata(data),
      raw_payload: account_data
    )
  end

  # Picks the balance that best represents "what the account is worth now".
  #
  # Banks return several balanceType values and not all return the same set, so this
  # prefers the interim available figure (what most banks show in-app), then the booked
  # closing figure, then anything at all. Without this ordering the balance shown depends
  # on arbitrary array order and can silently disagree with the bank's own app.
  BALANCE_TYPE_PRIORITY = %w[interimAvailable closingBooked interimBooked expected openingBooked forwardAvailable].freeze

  def extract_balance(balances)
    return nil if balances.blank?

    normalised = balances.map { |b| b.respond_to?(:with_indifferent_access) ? b.with_indifferent_access : b }

    chosen = BALANCE_TYPE_PRIORITY.lazy.filter_map { |type|
      normalised.find { |b| b[:balanceType].to_s == type }
    }.first || normalised.first

    parse_decimal(chosen.dig(:balanceAmount, :amount))
  end

  def upsert_gocardless_transactions_snapshot!(transactions_snapshot)
    assign_attributes(
      raw_transactions_payload: transactions_snapshot
    )

    save!
  end

  private

    def extract_institution_metadata(data)
      {
        name: data[:institution_name] || data.dig(:institution, :name),
        logo: data[:institution_logo] || data.dig(:institution, :logo),
        domain: data[:institution_domain] || data.dig(:institution, :domain)
      }.compact
    end

    def enqueue_connection_cleanup
      return unless gocardless_item

      GocardlessConnectionCleanupJob.perform_later(
        gocardless_item_id: gocardless_item.id,
        account_id: id
      )
    end

    def log_invalid_currency(currency_value)
      Rails.logger.warn("Invalid currency code '#{currency_value}' for Gocardless account #{id}, defaulting to USD")
    end
end
