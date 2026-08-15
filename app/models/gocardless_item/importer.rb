# frozen_string_literal: true

class GocardlessItem::Importer
  include SyncStats::Collector
  include GocardlessAccount::DataHelpers

  attr_reader :gocardless_item, :gocardless_provider, :sync

  def initialize(gocardless_item, gocardless_provider:, sync: nil)
    @gocardless_item = gocardless_item
    @gocardless_provider = gocardless_provider
    @sync = sync
  end

  class CredentialsError < StandardError; end

  def import
    Rails.logger.info "GocardlessItem::Importer - Starting import for item #{gocardless_item.id}"

    credentials = gocardless_item.gocardless_credentials
    unless credentials
      raise CredentialsError, "No Gocardless credentials configured for item #{gocardless_item.id}"
    end

    # Step 1: Fetch and store all accounts
    import_accounts(credentials)

    # Step 2: For LINKED accounts only, fetch data
    # Unlinked accounts just need basic info (name, balance) for the setup modal
    linked_accounts = GocardlessAccount
      .where(gocardless_item_id: gocardless_item.id)
      .joins(:account_provider)

    Rails.logger.info "GocardlessItem::Importer - Found #{linked_accounts.count} linked accounts to process"

    linked_accounts.each do |gocardless_account|
      Rails.logger.info "GocardlessItem::Importer - Processing linked account #{gocardless_account.id}"
      import_account_data(gocardless_account, credentials)
    end

    # Update raw payload on the item
    gocardless_item.upsert_gocardless_snapshot!(stats)
  rescue Provider::Gocardless::AuthenticationError => e
    gocardless_item.update!(status: :requires_update)
    raise
  end

  private

    def stats
      @stats ||= {}
    end

    def persist_stats!
      return unless sync&.respond_to?(:sync_stats)
      merged = (sync.sync_stats || {}).merge(stats)
      sync.update_columns(sync_stats: merged)
    end

    def import_accounts(credentials)
      Rails.logger.info "GocardlessItem::Importer - Fetching accounts"

      # TODO: Implement API call to fetch accounts
      # accounts_data = gocardless_provider.list_accounts(...)
      accounts_data = []

      stats["api_requests"] = stats.fetch("api_requests", 0) + 1
      stats["total_accounts"] = accounts_data.size

      # Track upstream account IDs to detect removed accounts
      upstream_account_ids = []

      accounts_data.each do |account_data|
        begin
          import_account(account_data, credentials)
          # TODO: Extract account ID from your provider's response format
          # upstream_account_ids << account_data[:id].to_s if account_data[:id]
        rescue => e
          Rails.logger.error "GocardlessItem::Importer - Failed to import account: #{e.message}"
          stats["accounts_skipped"] = stats.fetch("accounts_skipped", 0) + 1
          register_error(e, account_data: account_data)
        end
      end

      persist_stats!

      # Clean up accounts that no longer exist upstream
      prune_removed_accounts(upstream_account_ids)
    end

    def import_account(account_data, credentials)
      # TODO: Customize based on your provider's account ID field
      # gocardless_account_id = account_data[:id].to_s
      # return if gocardless_account_id.blank?

      # gocardless_account = gocardless_item.gocardless_accounts.find_or_initialize_by(
      #   gocardless_account_id: gocardless_account_id
      # )

      # Update from API data
      # gocardless_account.upsert_from_gocardless!(account_data)

      stats["accounts_imported"] = stats.fetch("accounts_imported", 0) + 1
    end

    def import_account_data(gocardless_account, credentials)
      # Import transactions
      import_transactions(gocardless_account, credentials)
    end

    def import_transactions(gocardless_account, credentials)
      Rails.logger.info "GocardlessItem::Importer - Fetching transactions for account #{gocardless_account.id}"

      begin
        # Determine date range
        start_date = calculate_transaction_start_date(gocardless_account)
        end_date = Date.current

        # TODO: Implement API call to fetch transactions
        # transactions_data = gocardless_provider.get_transactions(
        #   account_id: gocardless_account.gocardless_account_id,
        #   start_date: start_date,
        #   end_date: end_date
        # )
        transactions_data = []

        stats["api_requests"] = stats.fetch("api_requests", 0) + 1

        if transactions_data.any?
          # Convert SDK objects to hashes and merge with existing
          transactions_hashes = transactions_data.map { |t| sdk_object_to_hash(t) }
          merged = merge_transactions(gocardless_account.raw_transactions_payload || [], transactions_hashes)
          gocardless_account.upsert_gocardless_transactions_snapshot!(merged)
          stats["transactions_found"] = stats.fetch("transactions_found", 0) + transactions_data.size
        end
      rescue => e
        Rails.logger.warn "GocardlessItem::Importer - Failed to fetch transactions: #{e.message}"
        register_error(e, context: "transactions", account_id: gocardless_account.id)
      end
    end

    def calculate_transaction_start_date(gocardless_account)
      # Use user-specified start date if available
      user_start = gocardless_account.sync_start_date
      return user_start if user_start.present?

      # For accounts with existing transactions, use incremental sync
      existing_count = (gocardless_account.raw_transactions_payload || []).size
      if existing_count >= 10 && gocardless_item.last_synced_at.present?
        # Incremental: go back 7 days from last sync to catch updates
        (gocardless_item.last_synced_at - 7.days).to_date
      else
        # Full sync: go back 90 days
        90.days.ago.to_date
      end
    end

    def merge_transactions(existing, new_transactions)
      # Merge by ID, preferring newer data
      by_id = {}
      existing.each { |t| by_id[transaction_key(t)] = t }
      new_transactions.each { |t| by_id[transaction_key(t)] = t }
      by_id.values
    end

    def transaction_key(transaction)
      transaction = transaction.with_indifferent_access if transaction.is_a?(Hash)
      # Use ID if available, otherwise generate key from date/amount/description
      transaction[:id] || transaction["id"] ||
        [ transaction[:date], transaction[:amount], transaction[:description] ].join("-")
    end

    def prune_removed_accounts(upstream_account_ids)
      return if upstream_account_ids.empty?

      # Find accounts that exist locally but not upstream
      removed = gocardless_item.gocardless_accounts
        .where.not(gocardless_account_id: upstream_account_ids)

      if removed.any?
        Rails.logger.info "GocardlessItem::Importer - Pruning #{removed.count} removed accounts"
        removed.destroy_all
      end
    end

    def register_error(error, **context)
      stats["errors"] ||= []
      stats["errors"] << {
        message: error.message,
        context: context.to_s,
        timestamp: Time.current.iso8601
      }
    end
end
