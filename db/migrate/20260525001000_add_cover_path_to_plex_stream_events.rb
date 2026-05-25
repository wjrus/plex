class AddCoverPathToPlexStreamEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :plex_stream_events, :cover_path, :string
  end
end
