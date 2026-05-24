require "test_helper"

class RefreshRunTest < ActiveSupport::TestCase
  test "finds latest and active runs for a machine" do
    completed = RefreshRun.create!(machine_identifier: "machine-one", status: "completed", finished_at: 1.hour.ago)
    queued = RefreshRun.create!(machine_identifier: "machine-one", status: "queued")
    RefreshRun.create!(machine_identifier: "machine-two", status: "running")

    assert_equal queued, RefreshRun.latest_for("machine-one")
    assert_equal queued, RefreshRun.active_for("machine-one")
    assert_not completed.active?
  end
end
