class AddMetadataToPlexStreamEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :plex_stream_events, :metadata, :jsonb, default: {}, null: false
  end
end
