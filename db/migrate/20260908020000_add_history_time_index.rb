class AddHistoryTimeIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :plex_stream_events, [ :machine_identifier, :viewed_at ],
      name: "index_stream_events_on_machine_viewed", algorithm: :concurrently
  end
end
