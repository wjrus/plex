require "test_helper"

class PlexNowPlayingSampleTest < ActiveSupport::TestCase
  test "records current playback sessions" do
    sessions = [
      {
        title: "Episode",
        grandparent_title: "Show",
        type: "episode",
        library_section_title: "TV Shows",
        duration: "1000",
        view_offset: "500",
        rating_key: "123",
        user: { id: "42", title: "Viewer" },
        player: { title: "Apple TV", platform: "tvOS", address: "192.0.2.10", state: "playing" },
        session: { id: "session-one" }
      }
    ]

    assert_difference -> { PlexNowPlayingSample.count }, 1 do
      assert_equal 1, PlexNowPlayingSample.record_sessions!("machine-one", sessions, sampled_at: Time.zone.local(2026, 5, 25, 12, 0, 0))
    end

    sample = PlexNowPlayingSample.last
    assert_equal "machine-one", sample.machine_identifier
    assert_equal "session-one", sample.session_id
    assert_equal "42", sample.account_id
    assert_equal "Viewer", sample.user_label
    assert_equal "Apple TV", sample.player_title
    assert_equal "tvOS", sample.player_platform
    assert_equal "192.0.2.10", sample.ip_address
    assert_equal "Show - Episode", sample.full_title
    assert_equal 50, sample.progress_percent
    assert_equal "playing", sample.state
  end

  test "prunes samples older than retention cutoff" do
    PlexNowPlayingSample.create!(
      machine_identifier: "machine-one",
      sampled_at: 91.days.ago,
      session_id: "old"
    )
    PlexNowPlayingSample.create!(
      machine_identifier: "machine-one",
      sampled_at: 2.days.ago,
      session_id: "new"
    )

    assert_difference -> { PlexNowPlayingSample.count }, -1 do
      assert_equal 1, PlexNowPlayingSample.prune!(older_than: 90.days.ago)
    end
    assert_equal [ "new" ], PlexNowPlayingSample.pluck(:session_id)
  end
end
