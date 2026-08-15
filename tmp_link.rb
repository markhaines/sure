user = User.find_by!(email: "mark@larchway.com")
Current.session = user.sessions.first
raise "no session for the browser user" unless Current.family

f = Current.family
provider = Provider::GocardlessAdapter.build_provider(family: f)

# Revoke and remove abandoned consents (picker entered but never completed).
f.gocardless_items.where(requisition_status: "CR").each do |dupe|
  begin
    provider.delete_requisition(requisition_id: dupe.requisition_id)
    puts "revoked abandoned requisition #{dupe.requisition_id[0, 8]}"
  rescue Provider::Gocardless::GocardlessError => e
    puts "could not revoke #{dupe.id[0, 8]}: #{e.message}"
  end
  dupe.destroy!
end

item = f.gocardless_items.where(requisition_status: "LN").first
ctrl = GocardlessItemsController.new

item.unlinked_gocardless_accounts.order(:name).each do |ga|
  type = ctrl.send(:infer_accountable_type, ga.account_type)
  account = ctrl.send(:create_account_from_gocardless, ga, type, {})
  ga.ensure_account_provider!(account)
  puts "linked #{ga.name.ljust(24)} -> #{type}"
end

item.update(pending_account_setup: false)

puts "--- resulting accounts ---"
f.accounts.reload.each do |a|
  puts "#{a.accountable_type.ljust(11)} #{a.name.ljust(24)} balance=#{a.balance} #{a.currency} classification=#{a.classification}"
end
