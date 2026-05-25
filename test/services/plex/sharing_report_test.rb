require "test_helper"

module Plex
  class SharingReportTest < ActiveSupport::TestCase
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
            allow_sync: "1",
            servers: [ { id: "99", machine_identifier: "machine-one", last_seen_at: "1556281940" } ]
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
            type: "episode",
            grandparent_title: "Taskmaster",
            title: "The Noise That Blue Makes"
          }
        ]
      end
    end

    test "builds users with concrete libraries" do
      with_history_env do
      client = FakeClient.new(
        server_payload: {
          server: { name: "Local Plex" },
          sections: [
            { id: "1", key: "/library/sections/1", title: "Movies", type: "movie" },
            { id: "2", key: "/library/sections/2", title: "Shows", type: "show" }
          ]
        },
        shared_payload: [
          {
            user: { id: "42", title: "Viewer", username: "viewer" },
            id: "99",
            pending: "0",
            all_libraries: "0",
            sections: [ { id: "1", shared: "0" }, { id: "2", shared: "1" } ]
          }
        ]
      )

      report = SharingReport.new(client: client, machine_identifier: "machine-one").call

      assert_equal "Local Plex", report.server[:name]
      assert_equal [ "Movies", "Shows" ], report.libraries.map(&:title)
      assert_equal "99", report.users.first.share_id
      assert_equal "viewer@example.com", report.users.first.email
      assert_equal "1556281940", report.users.first.last_seen_at
      assert_equal "1556281941", report.users.first.last_streamed_at
      assert_equal "Taskmaster - The Noise That Blue Makes", report.users.first.last_streamed_title
      assert_equal [ "Shows" ], report.users.first.libraries.map(&:title)
      assert_not report.users.first.all_libraries
      end
    end

    test "prefers explicit shared sections over all libraries flag" do
      with_history_env do
      client = FakeClient.new(
        server_payload: {
          server: { name: "Local Plex" },
          sections: [
            { id: "1", key: "/library/sections/1", title: "4K Movies", type: "movie" },
            { id: "2", key: "/library/sections/2", title: "Movies", type: "movie" }
          ]
        },
        shared_payload: [
          {
            user: { id: "42", title: "Viewer", username: "viewer" },
            id: "99",
            pending: "0",
            all_libraries: "0",
            sections: [ { id: "1", shared: "0" }, { id: "2", shared: "1" } ]
          }
        ]
      )

      report = SharingReport.new(client: client, machine_identifier: "machine-one").call

      assert_equal [ "Movies" ], report.users.first.libraries.map(&:title)
      assert_not report.users.first.all_libraries
      end
    end

    test "allows all history with explicit env value" do
      with_history_env do
        ENV["PLEX_HISTORY_DAYS"] = "all"
        report = SharingReport.new(
          client: FakeClient.new(server_payload: { server: {}, sections: [] }, shared_payload: []),
          machine_identifier: "machine-one"
        )

        assert_nil report.send(:history_viewed_after)
      end
    end

    test "includes pending requested invites for the server" do
      with_history_env do
        client = FakeClient.new(
          server_payload: {
            server: { name: "Local Plex" },
            sections: [
              { id: "1", key: "1", title: "Movies", type: "movie" },
              { id: "2", key: "2", title: "Shows", type: "show" }
            ]
          },
          shared_payload: []
        )
        client.define_singleton_method(:requested_invites) do
          [
            {
              id: "invite-one",
              username: "pending-user",
              email: "pending@example.com",
              friendly_name: "Pending User",
              created_at: "1704307031",
              server: "1",
              home: "0",
              servers: [ { name: "Renamed Server", machine_identifier: "machine-one", num_libraries: "2" } ]
            }
          ]
        end

        report = SharingReport.new(client: client, machine_identifier: "machine-one").call
        user = report.users.first

        assert_predicate user, :pending
        assert_equal "pending-user", user.label
        assert_equal "1704307031", user.invited_at
        assert_equal [ "Movies", "Shows" ], user.libraries.map(&:title)
      end
    end

    private

    def with_history_env
      old_page_size = ENV["PLEX_HISTORY_PAGE_SIZE"]
      old_max_pages = ENV["PLEX_HISTORY_MAX_PAGES"]
      old_history_days = ENV["PLEX_HISTORY_DAYS"]
      ENV["PLEX_HISTORY_PAGE_SIZE"] = "200"
      ENV["PLEX_HISTORY_MAX_PAGES"] = "20"
      ENV.delete("PLEX_HISTORY_DAYS")
      yield
    ensure
      ENV["PLEX_HISTORY_PAGE_SIZE"] = old_page_size
      ENV["PLEX_HISTORY_MAX_PAGES"] = old_max_pages
      ENV["PLEX_HISTORY_DAYS"] = old_history_days
    end
  end
end
