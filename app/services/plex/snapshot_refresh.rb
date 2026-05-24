module Plex
  class SnapshotRefresh
    def initialize(client:, machine_identifier:, progress: nil, include_history: true)
      @client = client
      @machine_identifier = machine_identifier
      @progress = progress
      @include_history = include_history
    end

    def call
      report = SharingReport.new(
        client: client,
        machine_identifier: machine_identifier,
        progress: progress,
        include_history: include_history
      ).call
      previous_users = previous_streams_by_user_id

      ShareSnapshot.create!(
        machine_identifier: machine_identifier,
        server: stringify(report.server),
        libraries: report.libraries.map { |library| stringify(library.to_h) },
        users: report.users.map { |user| stringify(snapshot_user(user, previous_users)) },
        fetched_at: report.generated_at
      )
    end

    private

    attr_reader :client, :machine_identifier, :progress, :include_history

    def snapshot_user(user, previous_users)
      attributes = user.to_h.merge(libraries: user.libraries.map(&:to_h))
      return attributes if attributes[:last_streamed_at].present?

      previous = previous_users[user.id.to_s]
      return attributes unless previous

      attributes.merge(
        last_streamed_at: previous["last_streamed_at"],
        last_streamed_title: previous["last_streamed_title"],
        last_streamed_type: previous["last_streamed_type"]
      )
    end

    def previous_streams_by_user_id
      ShareSnapshot.where(machine_identifier: machine_identifier).latest_first.each_with_object({}) do |snapshot, streams|
        snapshot.users.each do |user|
          next if streams.key?(user["id"].to_s)
          next if user["last_streamed_at"].blank?

          streams[user["id"].to_s] = user
        end
      end
    end

    def stringify(value)
      value.deep_stringify_keys
    end
  end
end
