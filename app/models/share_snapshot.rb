class ShareSnapshot < ApplicationRecord
  validates :machine_identifier, :fetched_at, presence: true

  scope :latest_first, -> { order(fetched_at: :desc, created_at: :desc) }

  def self.latest_for(machine_identifier)
    where(machine_identifier: machine_identifier).latest_first.first
  end

  def self.checkpoint_streams!(machine_identifier, streams)
    snapshot = latest_for(machine_identifier)
    return unless snapshot && streams.present?

    changed = false
    users = snapshot.users.map do |user|
      stream = streams[user["id"].to_s]
      next user unless stream && stream[:viewed_at].present?
      next user if user["last_streamed_at"].to_i >= stream[:viewed_at].to_i

      changed = true
      user.merge(
        "last_streamed_at" => stream[:viewed_at],
        "last_streamed_title" => stream_title(stream),
        "last_streamed_type" => stream[:type]
      )
    end
    return unless changed

    create!(
      machine_identifier: snapshot.machine_identifier,
      server: snapshot.server,
      libraries: snapshot.libraries,
      users: users,
      fetched_at: Time.current
    )
  end

  def to_report
    Plex::SharingReport::Report.new(
      server: server.symbolize_keys,
      libraries: libraries.map { |library| Plex::SharingReport::Library.new(**library.symbolize_keys) },
      users: users.map { |user| snapshot_user(user) },
      generated_at: fetched_at
    )
  end

  private

  def self.stream_title(stream)
    [ stream[:grandparent_title], stream[:parent_title], stream[:title] ].compact_blank.join(" - ")
  end

  def snapshot_user(user)
    attributes = user.symbolize_keys
    library_rows = attributes.delete(:libraries) || []

    Plex::SharingReport::SharedUser.new(
      id: attributes[:id],
      share_id: attributes[:share_id],
      title: attributes[:title],
      username: attributes[:username],
      email: attributes[:email],
      thumb: attributes[:thumb],
      home: attributes[:home],
      restricted: attributes[:restricted],
      allow_sync: attributes[:allow_sync],
      allow_channels: attributes[:allow_channels],
      last_seen_at: attributes[:last_seen_at],
      last_streamed_at: attributes[:last_streamed_at],
      last_streamed_title: attributes[:last_streamed_title],
      last_streamed_type: attributes[:last_streamed_type],
      invited_at: attributes[:invited_at],
      invite_friend: attributes[:invite_friend],
      invite_server: attributes[:invite_server],
      pending: attributes[:pending],
      all_libraries: attributes[:all_libraries],
      library_count: attributes[:library_count],
      libraries: library_rows.map { |library| Plex::SharingReport::Library.new(**library.symbolize_keys) }
    )
  end
end
