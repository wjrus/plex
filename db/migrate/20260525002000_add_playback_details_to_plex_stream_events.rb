class AddPlaybackDetailsToPlexStreamEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :plex_stream_events, :player_title, :string
    add_column :plex_stream_events, :player_platform, :string
    add_column :plex_stream_events, :ip_address, :string
  end
end
