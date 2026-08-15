user = User.find_by!(email: "mark@larchway.com")
Current.session = user.sessions.first
f = Current.family
item = f.gocardless_items.where(requisition_status: "LN").first

# Re-derive from the stored raw payload, then push the corrected balance onto the linked
# Sure account so the balance sheet reflects it.
item.gocardless_accounts.each do |ga|
  ga.upsert_from_gocardless!(ga.raw_payload)
  acct = ga.account_provider&.account
  acct&.update!(balance: ga.current_balance)
  puts "#{ga.name.ljust(24)} provider=#{ga.current_balance} account=#{acct&.balance} (#{acct&.accountable_type})"
end

sheet = f.reload.balance_sheet
puts "---"
puts "assets:      #{sheet.assets.total_money}"
puts "liabilities: #{sheet.liabilities.total_money}"
puts "net worth:   #{sheet.net_worth_money}"
