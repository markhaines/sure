# Links the imported provider accounts to real Sure accounts, using the same controller
# helpers the UI would, so this exercises the real code path rather than a shortcut.
ctrl = GocardlessItemsController.new
item = Family.first.gocardless_items.where(requisition_status: "LN").first

item.unlinked_gocardless_accounts.order(:name).each do |ga|
  type = ctrl.send(:infer_accountable_type, ga.account_type)
  puts "#{ga.name} | cashAccountType=#{ga.account_type} -> #{type} | balance=#{ga.current_balance}"
end
