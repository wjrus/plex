require "test_helper"

class Plex::StreamFormatterTest < ActiveSupport::TestCase
  test "extracts player ip address" do
    stream = { player: { address: "192.0.2.10", remote_public_address: "198.51.100.20" } }

    assert_equal "192.0.2.10", Plex::StreamFormatter.ip_address(stream)
  end

  test "falls back to remote public player address" do
    stream = { player: { remote_public_address: "198.51.100.20" } }

    assert_equal "198.51.100.20", Plex::StreamFormatter.ip_address(stream)
  end

  test "infers started time from view offset" do
    now = Time.zone.local(2026, 5, 25, 12, 0, 0)
    stream = { view_offset: "120000" }

    assert_equal Time.zone.local(2026, 5, 25, 11, 58, 0), Plex::StreamFormatter.started_at(stream, now: now)
  end

  test "prefers explicit started time" do
    stream = { session: { started_at: "1779710400" }, view_offset: "120000" }

    assert_equal Time.zone.at(1_779_710_400), Plex::StreamFormatter.started_at(stream)
  end
end
