class CreatePlexStreamEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :plex_stream_events do |t|
      t.string :machine_identifier, null: false
      t.string :account_id, null: false
      t.string :rating_key
      t.string :media_type
      t.string :title
      t.string :full_title
      t.string :library_title
      t.integer :duration
      t.integer :view_offset
      t.datetime :viewed_at, null: false

      t.timestamps
    end

    add_index :plex_stream_events, [ :machine_identifier, :account_id, :viewed_at, :rating_key ],
      unique: true,
      name: "index_stream_events_on_machine_account_viewed_rating"
    add_index :plex_stream_events, [ :machine_identifier, :account_id, :viewed_at ],
      name: "index_stream_events_on_machine_account_viewed"
  end
end
