class PlexStreamEvent < ApplicationRecord
  validates :machine_identifier, :account_id, :viewed_at, presence: true

  scope :recent, -> { order(viewed_at: :desc, id: :desc) }
  scope :for_machine, ->(machine_identifier) { where(machine_identifier: machine_identifier) }

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
        cover_path: stream_cover_path(stream),
        library_title: stream[:library_section_title].presence,
        player_title: stream_player_title(stream),
        player_platform: stream_player_platform(stream),
        ip_address: stream_ip_address(stream),
        duration: stream[:duration].presence&.to_i,
        view_offset: stream[:view_offset].presence&.to_i,
        viewed_at: Time.zone.at(viewed_at.to_i),
        created_at: Time.current,
        updated_at: Time.current
      }
    end
    return if rows.empty?

    rows = rows.reverse.uniq do |row|
      [
        row[:machine_identifier],
        row[:account_id],
        row[:viewed_at],
        row[:rating_key]
      ]
    end.reverse

    upsert_all(rows, unique_by: :index_stream_events_on_machine_account_viewed_rating)
  end

  def label
    full_title.presence || title.presence || "Unknown title"
  end

  def player_label
    [ player_title, player_platform ].compact_blank.join(" · ").presence || "Unknown"
  end

  def self.history_summary(machine_identifier)
    scope = for_machine(machine_identifier)
    {
      total: scope.count,
      oldest: scope.minimum(:viewed_at),
      newest: scope.maximum(:viewed_at),
      with_player: scope.where.not(player_title: [ nil, "" ]).or(scope.where.not(player_platform: [ nil, "" ])).count,
      with_ip: scope.where.not(ip_address: [ nil, "" ]).count
    }
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

  def self.stream_cover_path(stream)
    stream[:grandparent_thumb].presence ||
      stream[:thumb].presence ||
      stream[:parent_thumb].presence ||
      stream[:art].presence
  end

  def self.stream_player_title(stream)
    player = stream[:player].is_a?(Hash) ? stream[:player] : {}
    player[:title].presence ||
      stream[:player_title].presence ||
      stream[:player].presence ||
      stream[:device].presence
  end

  def self.stream_player_platform(stream)
    player = stream[:player].is_a?(Hash) ? stream[:player] : {}
    player[:platform].presence ||
      stream[:player_platform].presence ||
      stream[:platform].presence
  end

  def self.stream_ip_address(stream)
    player = stream[:player].is_a?(Hash) ? stream[:player] : {}
    player[:address].presence ||
      stream[:ip_address].presence ||
      stream[:ip].presence ||
      stream[:address].presence
  end
end
