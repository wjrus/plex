module Plex
  class SnapshotRefresh
    def initialize(client:, machine_identifier:, progress: nil, include_history: true)
      @client = client
      @machine_identifier = machine_identifier
      @progress = progress
      @include_history = include_history
    end

    def call
      SharingReport.new(
        client: client, machine_identifier: machine_identifier,
        include_history: include_history, progress: method(:record_history_page)
      ).history_streams

      ShareSnapshot.with_server_lock(machine_identifier) { refresh_shares }
    end

    private

    def refresh_shares
      report = SharingReport.new(
        client: client,
        machine_identifier: machine_identifier,
        progress: progress,
        include_history: false
      ).call
      previous_users = previous_streams_by_user_id(report.users.map { |user| user.id.to_s })

      ShareSnapshot.create!(
        machine_identifier: machine_identifier,
        server: stringify(report.server),
        libraries: report.libraries.map { |library| stringify(library.to_h) },
        users: report.users.map { |user| stringify(snapshot_user(user, previous_users)) },
        fetched_at: report.generated_at
      )
    end

    attr_reader :client, :machine_identifier, :progress, :include_history

    def record_history_page(event)
      PlexStreamEvent.upsert_streams!(machine_identifier, event.fetch(:page_streams))
      ShareSnapshot.checkpoint_streams!(machine_identifier, event.fetch(:streams))
      progress&.call(event)
    end

    def snapshot_user(user, previous_users)
      attributes = user.to_h.merge(libraries: user.libraries.map(&:to_h))
      return attributes if attributes[:last_streamed_at].present?

      previous = previous_users[user.id.to_s]
      return attributes unless previous

      attributes.merge(
        last_streamed_at: previous["last_streamed_at"],
        last_streamed_title: previous["last_streamed_title"],
        last_streamed_type: previous["last_streamed_type"],
        invited_at: attributes[:invited_at]
      )
    end

    def previous_streams_by_user_id(user_ids)
      streams = Array(ShareSnapshot.latest_for(machine_identifier)&.users).index_by { |user| user["id"].to_s }
      PlexStreamEvent.latest_for_accounts(machine_identifier, user_ids).each do |event|
        previous = streams[event.account_id]
        next if previous && previous["last_streamed_at"].to_i >= event.viewed_at.to_i

        streams[event.account_id] = {
          "last_streamed_at" => event.viewed_at.to_i,
          "last_streamed_title" => event.label,
          "last_streamed_type" => event.media_type
        }
      end
      streams
    end

    def stringify(value)
      value.deep_stringify_keys
    end
  end
end
