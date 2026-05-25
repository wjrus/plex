require "test_helper"

class PlexStreamEventTest < ActiveSupport::TestCase
  test "upserts streams by machine account viewed time and rating key" do
    stream = {
      account_id: "42",
      rating_key: "abc",
      viewed_at: "1779649200",
      type: "movie",
      title: "Feature",
      library_section_title: "Movies",
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
end
