require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "localized time formats include the year" do
    time = Time.zone.local(2026, 5, 24, 13, 45, 0)

    assert_equal "May 24, 2026 13:45", l(time, format: :short)
    assert_equal "May 24, 2026 13:45", l(time, format: :long)
  end

  test "plex timestamps include the year" do
    timestamp = Time.zone.local(2026, 5, 24, 13, 45, 0).to_i

    assert_equal "May 24, 2026 13:45", plex_timestamp(timestamp)
  end
end
