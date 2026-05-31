class AddOperationalGovernanceToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :role, :string, null: false, default: "operator"
    add_check_constraint :users, "role IN ('viewer', 'operator', 'admin')", name: "users_role_check"
    add_index :users, :role
  end
end
