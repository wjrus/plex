require "test_helper"

class PlexStreamEventTest < ActiveSupport::TestCase
  test "upserts streams by machine account viewed time and rating key" do
    stream = {
      account_id: "42",
      rating_key: "abc",
      viewed_at: "1779649200",
      type: "movie",
      title: "Feature",
      thumb: "/library/metadata/1/thumb/123",
      library_section_title: "Movies",
      player: { title: "Apple TV", platform: "tvOS", address: "192.0.2.10" },
      duration: "1000",
      view_offset: "800"
    }

    assert_difference -> { PlexStreamEvent.count }, 1 do
      PlexStreamEvent.upsert_streams!("machine-one", [ stream ])
      PlexStreamEvent.upsert_streams!("machine-one", [ stream.merge(title: "Feature Updated") ])
    end

    event = PlexStreamEvent.find_by!(machine_identifier: "machine-one", account_id: "42")
    assert_equal "Feature Updated", event.title
    assert_equal "Movies", event.library_title
    assert_equal "/library/metadata/1/thumb/123", event.cover_path
    assert_equal "Apple TV", event.player_title
    assert_equal "tvOS", event.player_platform
    assert_equal "Apple TV · tvOS", event.player_label
    assert_equal "192.0.2.10", event.ip_address
  end

  test "stores flat Plex history player fields" do
    stream = {
      account_id: "42",
      rating_key: "abc",
      viewed_at: "1779649200",
      type: "movie",
      title: "Feature",
      player: "Living Room Roku",
      platform: "Roku",
      ip_address: "198.51.100.4"
    }

    PlexStreamEvent.upsert_streams!("machine-one", [ stream ])

    event = PlexStreamEvent.find_by!(machine_identifier: "machine-one", account_id: "42")
    assert_equal "Living Room Roku", event.player_title
    assert_equal "Roku", event.player_platform
    assert_equal "198.51.100.4", event.ip_address
  end

  test "deduplicates streams inside one upsert batch" do
    stream = {
      account_id: "42",
      rating_key: "abc",
      viewed_at: "1779649200",
      type: "movie",
      title: "Feature",
      library_section_title: "Movies"
    }

    assert_difference -> { PlexStreamEvent.count }, 1 do
      PlexStreamEvent.upsert_streams!("machine-one", [ stream, stream.merge(title: "Feature Updated") ])
    end

    assert_equal "Feature Updated", PlexStreamEvent.find_by!(machine_identifier: "machine-one", account_id: "42").title
  end

  test "completed play scope counts one completion per user title and day" do
    attrs = {
      machine_identifier: "machine-one",
      account_id: "42",
      rating_key: "rating-one",
      full_title: "Feature",
      media_type: "movie",
      duration: 1000
    }
    PlexStreamEvent.create!(attrs.merge(viewed_at: Time.zone.local(2026, 5, 24, 10, 0, 0), view_offset: 100))
    PlexStreamEvent.create!(attrs.merge(viewed_at: Time.zone.local(2026, 5, 24, 10, 5, 0), view_offset: 500))
    PlexStreamEvent.create!(attrs.merge(viewed_at: Time.zone.local(2026, 5, 24, 10, 10, 0), view_offset: 950))
    PlexStreamEvent.create!(attrs.merge(viewed_at: Time.zone.local(2026, 5, 24, 10, 15, 0), view_offset: 980))

    scope = PlexStreamEvent.where(machine_identifier: "machine-one")
    assert_equal 1, PlexStreamEvent.completed_play_scope(scope).count
    assert_equal 1, PlexStreamEvent.history_summary("machine-one")[:completed_plays]
  end
end
