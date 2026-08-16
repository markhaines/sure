require "test_helper"

class UserTransactionColumnsTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
  end

  test "defaults preserve the previously hard-coded columns" do
    assert_equal User::DEFAULT_TRANSACTION_COLUMNS, @user.transaction_columns
    assert @user.show_transaction_column?("merchant")
    assert_not @user.show_transaction_column?("notes")
  end

  test "stores a selection" do
    @user.update_transaction_columns(%w[notes tags])

    assert_equal %w[notes tags], @user.reload.transaction_columns
    assert @user.show_transaction_column?("notes")
    assert_not @user.show_transaction_column?("merchant")
  end

  test "an empty selection is honoured rather than falling back to defaults" do
    # Turning everything off is a legitimate choice. Treating [] as "unset" would make
    # the last column impossible to hide.
    @user.update_transaction_columns([])

    assert_equal [], @user.reload.transaction_columns
    User::TRANSACTION_COLUMNS.each do |column|
      assert_not @user.show_transaction_column?(column), "#{column} should be hidden"
    end
  end

  test "ignores unknown column names" do
    @user.update_transaction_columns(%w[notes bobby_tables])

    assert_equal %w[notes], @user.reload.transaction_columns
  end

  test "drops columns the app no longer offers" do
    # Simulates a column being removed in a later version while still sitting in a
    # user's stored preferences.
    @user.update!(preferences: { "transaction_columns" => %w[notes retired_column] })

    assert_equal %w[notes], @user.transaction_columns
  end

  test "accepts symbols as well as strings" do
    @user.update_transaction_columns([ :tags ])

    assert_equal %w[tags], @user.reload.transaction_columns
    assert @user.show_transaction_column?(:tags)
  end

  test "does not disturb other preferences" do
    @user.update!(preferences: { "section_order" => %w[a b] })
    @user.update_transaction_columns(%w[notes])

    assert_equal %w[a b], @user.reload.preferences["section_order"]
    assert_equal %w[notes], @user.transaction_columns
  end
end
