require "test_helper"

# The snapshot dedup key. The generated default looked for :id/:date/:amount/:description,
# none of which GoCardless sends, so every transaction hashed to the same key and a whole
# statement collapsed to one row: 459 real transactions stored as 1. It fails silently,
# reporting a successful sync with almost no data.
class GocardlessItem::ImporterTest < ActiveSupport::TestCase
  setup do
    @importer = GocardlessItem::Importer.allocate
  end

  def key(attrs)
    @importer.send(:transaction_key, attrs.with_indifferent_access)
  end

  def txn(id: nil, amount: "-10.00", date: "2026-08-15", desc: "TESCO")
    {
      "transactionId" => id,
      "bookingDate" => date,
      "transactionAmount" => { "amount" => amount, "currency" => "GBP" },
      "remittanceInformationUnstructured" => desc
    }.compact
  end

  test "keys on the bank transaction id when present" do
    assert_equal "abc123", key(txn(id: "abc123"))
  end

  test "distinct transactions without ids do not collide" do
    a = key(txn(amount: "-10.00", desc: "TESCO"))
    b = key(txn(amount: "-20.00", desc: "TESCO"))
    c = key(txn(amount: "-10.00", desc: "SAINSBURYS"))

    assert_equal 3, [ a, b, c ].uniq.size, "different transactions must not share a key"
  end

  test "the same transaction keys identically so re-syncing does not duplicate" do
    assert_equal key(txn(id: "abc123")), key(txn(id: "abc123"))
  end

  test "falls back to internalTransactionId before the composite" do
    t = txn.merge("internalTransactionId" => "internal-1")

    assert_equal "internal-1", key(t)
  end

  test "merging a fetch into an existing snapshot keeps every distinct transaction" do
    existing = [ txn(id: "a"), txn(id: "b") ].map(&:with_indifferent_access)
    fetched = [ txn(id: "b"), txn(id: "c") ].map(&:with_indifferent_access)

    merged = @importer.send(:merge_transactions, existing, fetched)

    assert_equal 3, merged.size, "expected a, b, c with b de-duplicated"
  end
end
