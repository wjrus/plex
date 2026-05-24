require "test_helper"

class ShareAuditLogTest < ActiveSupport::TestCase
  test "builds readable summaries" do
    entry = ShareAuditLog.new(
      action: "libraries_removed",
      admin_email: "admin@example.com",
      target_label: "Viewer",
      libraries_removed: [ "Theatre" ],
      libraries_after: [ "Movies" ]
    )

    assert_equal "removed Theatre from Viewer", entry.summary
    assert_equal "Now shared: Movies", entry.details
  end

  test "records library names from snapshot hashes" do
    entry = ShareAuditLog.record!(
      action: "library_access_granted",
      admin_email: "admin@example.com",
      target: { label: "friend@example.com", email: "friend@example.com" },
      libraries_added: [ { "title" => "Movies" } ],
      libraries_after: [ { "title" => "Movies" } ]
    )

    assert_equal [ "Movies" ], entry.libraries_added
    assert_equal [ "Movies" ], entry.libraries_after
  end
end
