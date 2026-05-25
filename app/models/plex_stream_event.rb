class PlexStreamEvent < ApplicationRecord
  validates :machine_identifier, :account_id, :viewed_at, presence: true

  scope :recent, -> { order(viewed_at: :desc, id: :desc) }

  def self.for_user(machine_identifier, account_id, limit: 25)
    where(machine_identifier: machine_identifier, account_id: account_id.to_s)
      .recent
      .limit(limit)
  end

  def self.upsert_streams!(machine_identifier, streams)
    rows = Array(streams).filter_map do |stream|
      account_id = stream[:account_id].to_s.presence
      viewed_at = stream[:viewed_at].presence
      next unless account_id && viewed_at

      {
        machine_identifier: machine_identifier,
        account_id: account_id,
        rating_key: stream_identifier(stream),
        media_type: stream[:type].presence,
        title: stream[:title].presence,
        full_title: stream_title(stream),
        library_title: stream[:library_section_title].presence,
        duration: stream[:duration].presence&.to_i,
        view_offset: stream[:view_offset].presence&.to_i,
        viewed_at: Time.zone.at(viewed_at.to_i),
        created_at: Time.current,
        updated_at: Time.current
      }
    end
    return if rows.empty?

    upsert_all(rows, unique_by: :index_stream_events_on_machine_account_viewed_rating)
  end

  def label
    full_title.presence || title.presence || "Unknown title"
  end

  def self.stream_title(stream)
    [ stream[:grandparent_title], stream[:parent_title], stream[:title] ].compact_blank.join(" - ")
  end

  def self.stream_identifier(stream)
    stream[:rating_key].presence ||
      stream[:key].presence ||
      stream[:guid].presence ||
      stream_title(stream).presence ||
      "unknown"
  end
end
