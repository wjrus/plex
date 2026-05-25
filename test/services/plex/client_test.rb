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

    test "parses playback history metadata with user and player details" do
      xml = <<~XML
        <MediaContainer size="1">
          <Video title="Feature" type="movie" viewedAt="1779649200" accountID="42" ratingKey="abc">
            <User id="42" title="Viewer" />
            <Player title="Apple TV" platform="tvOS" address="192.0.2.10" />
            <Media id="1" videoCodec="h264">
              <Part id="2" file="/media/feature.mkv" />
            </Media>
          </Video>
        </MediaContainer>
      XML
      client = Client.new(token: "token", server_base_url: "http://plex.example")

      history = client.send(:media_container, xml)[:metadata].first

      assert_equal "Feature", history[:title]
      assert_equal "42", history[:account_id]
      assert_equal "Viewer", history.dig(:user, :title)
      assert_equal "Apple TV", history.dig(:player, :title)
      assert_equal "tvOS", history.dig(:player, :platform)
      assert_equal "192.0.2.10", history.dig(:player, :address)
      assert_equal "h264", history.dig(:media, :video_codec)
      assert_equal "/media/feature.mkv", history.dig(:media, :part, :file)
    end

    test "parses json metadata with nested details" do
      payload = {
        "MediaContainer" => {
          "Metadata" => [
            {
              "title" => "Feature",
              "accountID" => "42",
              "Player" => { "title" => "Apple TV", "platform" => "tvOS" },
              "Media" => [
                { "videoCodec" => "h264", "Part" => [ { "file" => "/media/feature.mkv" } ] }
              ]
            }
          ]
        }
      }
      client = Client.new(token: "token", server_base_url: "http://plex.example")

      history = client.send(:media_container, JSON.generate(payload))[:metadata].first

      assert_equal "42", history[:account_id]
      assert_equal "Apple TV", history.dig(:player, :title)
      assert_equal "h264", history.dig(:media, 0, :video_codec)
      assert_equal "/media/feature.mkv", history.dig(:media, 0, :part, 0, :file)
    end

    test "escapes requested invite ids when canceling" do
      client = Client.new(token: "token")
      captured_path = nil
      captured_method = nil
      captured_params = nil
      client.define_singleton_method(:request) do |path, method:, params: {}|
        captured_path = path
        captured_method = method
        captured_params = params
        ""
      end

      client.cancel_requested_invite("pending@example.com", friend: false, home: false, server: true)

      assert_equal "/api/invites/requested/pending%40example.com", captured_path
      assert_equal :delete, captured_method
      assert_equal({ friend: 0, home: 0, server: 1 }, captured_params)
    end
  end
end
