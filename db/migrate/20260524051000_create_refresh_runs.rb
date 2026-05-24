class CreateRefreshRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :refresh_runs do |t|
      t.string :machine_identifier, null: false
      t.string :status, null: false
      t.string :admin_email
      t.boolean :include_history, null: false, default: false
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :history_pages_retrieved, null: false, default: 0
      t.integer :history_rows_retrieved, null: false, default: 0
      t.integer :history_users_matched, null: false, default: 0
      t.integer :history_users_remaining, null: false, default: 0
      t.integer :account_lookups_completed, null: false, default: 0
      t.integer :account_lookups_total, null: false, default: 0
      t.string :last_message
      t.text :error_message
      t.bigint :share_snapshot_id

      t.timestamps
    end

    add_index :refresh_runs, [ :machine_identifier, :created_at ]
    add_index :refresh_runs, :status
    add_index :refresh_runs, :share_snapshot_id
  end
end
