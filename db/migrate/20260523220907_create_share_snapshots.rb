class CreateShareSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :share_snapshots do |t|
      t.string :machine_identifier, null: false
      t.jsonb :server, null: false, default: {}
      t.jsonb :libraries, null: false, default: []
      t.jsonb :users, null: false, default: []
      t.datetime :fetched_at, null: false

      t.timestamps
    end

    add_index :share_snapshots, [ :machine_identifier, :fetched_at ]
  end
end
