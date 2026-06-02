class RequireFinancialCommandIdempotencyKeys < ActiveRecord::Migration[8.1]
  COMMAND_TABLES = %i[
    fundings
    transfers
    split_payments
    pix_payments
    payouts
    refunds
    med_cases
  ].freeze

  def up
    assert_no_blank_command_idempotency_keys!

    COMMAND_TABLES.each do |table_name|
      constraint_name = "#{table_name}_idempotency_key_required_check"

      add_check_constraint table_name,
        "idempotency_key IS NOT NULL AND btrim(idempotency_key) <> ''",
        name: constraint_name,
        validate: false

      validate_check_constraint table_name, name: constraint_name
    end
  end

  def down
    COMMAND_TABLES.each do |table_name|
      remove_check_constraint table_name,
        name: "#{table_name}_idempotency_key_required_check",
        if_exists: true
    end
  end

  private

  def assert_no_blank_command_idempotency_keys!
    union_sql = COMMAND_TABLES.map do |table_name|
      <<~SQL.squish
        SELECT '#{table_name}' AS table_name, COUNT(*) AS invalid_count
        FROM #{table_name}
        WHERE idempotency_key IS NULL OR btrim(idempotency_key) = ''
      SQL
    end.join(" UNION ALL ")

    invalid_tables = select_all(union_sql).filter_map do |row|
      count = row.fetch("invalid_count").to_i
      "#{row.fetch("table_name")}=#{count}" if count.positive?
    end

    return if invalid_tables.empty?

    raise ActiveRecord::IrreversibleMigration,
      "financial command rows without idempotency evidence: #{invalid_tables.join(', ')}"
  end
end
