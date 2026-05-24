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
      assert_equal "1556281941", snapshot.users.first["last_streamed_at"]
      assert_equal "Movies", snapshot.users.first["libraries"].first["title"]
    end

    test "preserves previous stream data when history lookup fails" do
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

      snapshot = SnapshotRefresh.new(client: client, machine_identifier: "machine-one").call

      assert_equal 1556281941, snapshot.users.first["last_streamed_at"]
      assert_equal "Movies - Feature", snapshot.users.first["last_streamed_title"]
    end
  end
end
