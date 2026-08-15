i = Family.first.gocardless_items.where(requisition_status: "LN").first
puts "http://192.168.10.34:3000/gocardless_items/#{i.id}/setup_accounts"
puts "unlinked: #{i.unlinked_gocardless_accounts.count} / #{i.gocardless_accounts.count}"
