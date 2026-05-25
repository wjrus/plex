require "test_helper"

class ShareSnapshotTest < ActiveSupport::TestCase
  test "latest_for returns newest snapshot for a machine identifier" do
    assert_equal share_snapshots(:one), ShareSnapshot.latest_for("machine-one")
  end

  test "to_report rebuilds Plex report objects" do
    report = share_snapshots(:one).to_report

    assert_equal "Local Plex", report.server[:name]
    assert_equal "Movies", report.libraries.first.title
    assert_equal "viewer", report.users.first.label
    assert_equal "99", report.users.first.share_id
    assert_equal 1556281940, report.users.first.last_seen_at
    assert_equal 1556281941, report.users.first.last_streamed_at
    assert_equal "Movies - Feature", report.users.first.last_streamed_title
    assert report.users.first.all_libraries
  end

  test "checkpoint_streams creates a newer snapshot with fresher stream data" do
    snapshot = ShareSnapshot.checkpoint_streams!(
      "machine-one",
      {
        "42" => {
          viewed_at: "1779593823",
          type: "episode",
          grandparent_title: "Show",
          title: "Episode"
        }
      }
    )

    assert_predicate snapshot, :persisted?
    assert_equal "1779593823", snapshot.users.first["last_streamed_at"]
    assert_equal "Show - Episode", snapshot.users.first["last_streamed_title"]
  end
end
