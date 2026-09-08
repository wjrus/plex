require "test_helper"

class ShareSnapshotTest < ActiveSupport::TestCase
  test "server lock excludes another connection but not another server" do
    with_competing_connection do |competitor|
      ShareSnapshot.with_server_lock("synthetic-lock") do
        assert_equal "f", try_lock(competitor, "synthetic-lock")
        assert_equal "t", try_lock(competitor, "another-server")
      end
      assert_equal "t", try_lock(competitor, "synthetic-lock")
      assert_raises(ShareSnapshot::BusyError) { ShareSnapshot.with_server_lock("synthetic-lock") { flunk } }
    end
  end

  test "server lock is released after exceptions and nested calls" do
    assert_raises(RuntimeError) do
      ShareSnapshot.with_server_lock("synthetic-lock") do
        ShareSnapshot.with_server_lock("synthetic-lock") { raise "Synthetic failure" }
      end
    end
    with_competing_connection { |competitor| assert_equal "t", try_lock(competitor, "synthetic-lock") }
  end

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

  private

  def with_competing_connection
    config = ShareSnapshot.connection_db_config.configuration_hash
    connection = PG.connect(dbname: config[:database], host: config[:host], port: config[:port],
      user: config[:username], password: config[:password])
    yield connection
  ensure
    connection&.close
  end

  def try_lock(connection, machine)
    connection.exec_params("SELECT pg_try_advisory_lock(hashtextextended($1, 0))", [ "plex:shares:#{machine}" ]).getvalue(0, 0)
  end
end
