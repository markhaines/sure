item = Family.first.gocardless_items.where(requisition_status: "LN").first
begin
  html = ApplicationController.render(
    template: "gocardless_items/setup_accounts",
    assigns: {
      gocardless_item: item,
      unlinked_accounts: item.unlinked_gocardless_accounts.order(:name)
    },
    layout: false
  )
  puts "RENDER OK, #{html.length} bytes"
  item.gocardless_accounts.each do |a|
    puts "  #{a.name}: #{html.include?(a.name) ? 'present' : 'MISSING'}"
  end
rescue => e
  puts "RENDER FAILED: #{e.class}: #{e.message}"
  puts e.backtrace.grep(/workspace/).first(2)
end
