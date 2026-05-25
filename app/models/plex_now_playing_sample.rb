class PlexNowPlayingSample < ApplicationRecord
  validates :machine_identifier, :sampled_at, presence: true

  scope :recent, -> { order(sampled_at: :desc, id: :desc) }

  def self.record_sessions!(machine_identifier, sessions, sampled_at: Time.current)
    rows = Array(sessions).map do |stream|
      {
        machine_identifier: machine_identifier,
        sampled_at: sampled_at,
        session_id: stream.dig(:session, :id).presence,
        account_id: stream.dig(:user, :id).presence || stream[:account_id].presence,
        user_label: Plex::StreamFormatter.user_label(stream),
        player_title: stream.dig(:player, :title).presence,
        player_platform: stream.dig(:player, :platform).presence,
        ip_address: stream.dig(:player, :address).presence,
        state: Plex::StreamFormatter.state(stream),
        rating_key: PlexStreamEvent.stream_identifier(stream),
        media_type: stream[:type].presence,
        title: stream[:title].presence,
        full_title: Plex::StreamFormatter.title(stream).presence,
        library_title: stream[:library_section_title].presence,
        duration: stream[:duration].presence&.to_i,
        view_offset: stream[:view_offset].presence&.to_i,
        progress_percent: Plex::StreamFormatter.progress_percent(stream),
        metadata: stream,
        created_at: Time.current,
        updated_at: Time.current
      }
    end
    return 0 if rows.empty?

    insert_all!(rows)
    rows.size
  end
end
