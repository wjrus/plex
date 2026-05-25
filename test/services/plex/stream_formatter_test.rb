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
end
