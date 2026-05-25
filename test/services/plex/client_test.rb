require "test_helper"

module Plex
  class ClientTest < ActiveSupport::TestCase
    test "parses current playback sessions with user and player details" do
      xml = <<~XML
        <MediaContainer size="1">
          <Video title="Episode" grandparentTitle="Show" type="episode" duration="1000" viewOffset="250" librarySectionTitle="TV Shows">
            <User id="42" title="Viewer" />
            <Player title="Apple TV" platform="tvOS" state="playing" />
            <Session id="session-one" />
          </Video>
        </MediaContainer>
      XML
      client = Client.new(token: "token", server_base_url: "http://plex.example")

      session = client.send(:session_document, xml).first

      assert_equal "Episode", session[:title]
      assert_equal "Viewer", session.dig(:user, :title)
      assert_equal "Apple TV", session.dig(:player, :title)
      assert_equal "session-one", session.dig(:session, :id)
    end
  end
end
