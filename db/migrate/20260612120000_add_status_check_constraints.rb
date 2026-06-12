class AddStatusCheckConstraints < ActiveRecord::Migration[8.1]
  CHECKS = {
    customers: "status IN ('active', 'blocked', 'closed')",
    journal_entries: "status IN ('posted', 'reversed')",
    ledger_accounts: "status IN ('active', 'archived')",
    organizations: "status IN ('active', 'suspended')",
    wallets: "status IN ('active', 'blocked', 'closed')"
  }.freeze

  def up
    CHECKS.each do |table, expression|
      add_check_constraint table, expression, name: "#{table}_status_check", validate: false
      validate_check_constraint table, name: "#{table}_status_check"
    end
  end

  def down
    CHECKS.each_key do |table|
      remove_check_constraint table, name: "#{table}_status_check"
    end
  end
end
