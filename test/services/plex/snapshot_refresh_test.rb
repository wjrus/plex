require "test_helper"

module Plex
  class SnapshotRefreshTest < ActiveSupport::TestCase
    FakeClient = Struct.new(:server_payload, :shared_payload, keyword_init: true) do
      def server(_machine_identifier)
        server_payload
      end

      def shared_servers(_machine_identifier)
        shared_payload
      end

      def users
        [
          {
            id: "42",
            title: "Viewer",
            username: "viewer",
            email: "viewer@example.com",
            servers: [ { id: "99", machine_identifier: "machine-one" } ]
          }
        ]
      end

      def requested_invites
        []
      end

      def playback_history(size:, offset:, account_id: nil)
        return [] unless account_id.nil? && offset.zero?

        [
          {
            account_id: "42",
            viewed_at: "1556281941",
            type: "movie",
            title: "Feature"
          }
        ]
      end
    end

    TimeoutHistoryClient = Class.new(FakeClient) do
      def playback_history(size:, offset:, account_id: nil)
        raise Client::Error, "history timed out"
      end
    end

    test "persists a share snapshot from the Plex report" do
      client = FakeClient.new(
        server_payload: {
          server: { name: "Local Plex" },
          sections: [ { id: "1", key: "1", title: "Movies", type: "movie" } ]
        },
        shared_payload: [
          {
            user: { id: "42", title: "Viewer", username: "viewer" },
            id: "99",
            pending: "0",
            all_libraries: "1",
            sections: []
          }
        ]
      )

      snapshot = SnapshotRefresh.new(client: client, machine_identifier: "machine-one").call

      assert_predicate snapshot, :persisted?
      assert_equal "Local Plex", snapshot.server["name"]
      assert_equal "99", snapshot.users.first["share_id"]
      assert_equal "Viewer", snapshot.users.first["title"]
      assert_equal 1556281941, snapshot.users.first["last_streamed_at"].to_i
      assert_equal "Movies", snapshot.users.first["libraries"].first["title"]
    end

    test "ingests the whole window including owner history with no shares" do
      with_paged_history do
        client = FakeClient.new(server_payload: { server: {}, sections: [] }, shared_payload: [])
        calls = []
        now = Time.current.to_i
        client.define_singleton_method(:playback_history) do |size:, offset:, **_|
          calls << offset
          offset.zero? ? [
            { account_id: "42", rating_key: "a", viewed_at: now, title: "Feature" },
            { account_id: "owner", rating_key: "b", viewed_at: now, title: "Owner feature" }
          ] : [ { account_id: "42", rating_key: "c", viewed_at: now - 60, title: "Earlier feature" } ]
        end
        assert_difference "PlexStreamEvent.count", 3 do
          SnapshotRefresh.new(client: client, machine_identifier: "synthetic-history").call
        end
        assert_equal [ 0, 2 ], calls
        assert PlexStreamEvent.exists?(machine_identifier: "synthetic-history", account_id: "owner")
      end
    end

    test "a failed later page preserves already saved events and raises" do
      with_paged_history do
        client = FakeClient.new(server_payload: { server: {}, sections: [] }, shared_payload: [])
        now = Time.current.to_i
        client.define_singleton_method(:playback_history) do |size:, offset:, **_|
          raise Client::Error, "Synthetic timeout" unless offset.zero?

          [ "a", "b" ].map { |key| { account_id: "42", rating_key: key, viewed_at: now, title: "Feature" } }
        end
        assert_difference "PlexStreamEvent.count", 2 do
          assert_raises(Client::Error) { SnapshotRefresh.new(client: client, machine_identifier: "synthetic-history").call }
        end
      end
    end

    test "metadata refresh restores stored history while reading only the latest snapshot" do
      machine = "synthetic-archive"
      20.times do |index|
        ShareSnapshot.create!(machine_identifier: machine, server: {}, libraries: [], users: [], fetched_at: index.days.ago)
      end
      viewed_at = 1.hour.ago.change(usec: 0)
      PlexStreamEvent.upsert_streams!(machine, [
        { account_id: "42", rating_key: "feature", title: "Stored feature", type: "movie", viewed_at: viewed_at.to_i }
      ])
      client = TimeoutHistoryClient.new(
        server_payload: { server: {}, sections: [] },
        shared_payload: [ { user: { id: "42", username: "viewer" }, id: "99", pending: "0", sections: [] } ]
      )
      snapshot_reads = 0
      subscriber = ->(event) { snapshot_reads += event.payload[:record_count] if event.payload[:class_name] == "ShareSnapshot" }
      snapshot = nil
      ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
        snapshot = SnapshotRefresh.new(client: client, machine_identifier: machine, include_history: false).call
      end

      assert_equal 1, snapshot_reads
      user = snapshot.users.find { |row| row["id"].to_s == "42" }
      assert_equal viewed_at.to_i, user["last_streamed_at"]
      assert_equal "Stored feature", user["last_streamed_title"]
    end

    test "fails without replacing the snapshot when history lookup fails" do
      client = TimeoutHistoryClient.new(
        server_payload: {
          server: { name: "Local Plex" },
          sections: [ { id: "1", key: "1", title: "Movies", type: "movie" } ]
        },
        shared_payload: [
          {
            user: { id: "42", title: "Viewer", username: "viewer" },
            id: "99",
            pending: "0",
            all_libraries: "1",
            sections: []
          }
        ]
      )

      snapshot = ShareSnapshot.latest_for("machine-one")
      assert_raises(Client::Error) do
        SnapshotRefresh.new(client: client, machine_identifier: "machine-one").call
      end

      assert_equal snapshot, ShareSnapshot.latest_for("machine-one")
      assert_equal 1556281941, snapshot.users.first["last_streamed_at"]
      assert_equal "Movies - Feature", snapshot.users.first["last_streamed_title"]
    end

    private

    def with_paged_history
      original = ENV.to_h.slice("PLEX_HISTORY_DAYS", "PLEX_HISTORY_PAGE_SIZE")
      ENV["PLEX_HISTORY_DAYS"] = "1"
      ENV["PLEX_HISTORY_PAGE_SIZE"] = "2"
      yield
    ensure
      %w[PLEX_HISTORY_DAYS PLEX_HISTORY_PAGE_SIZE].each { |key| ENV[key] = original[key] }
    end
  end
end
