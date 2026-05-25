require "test_helper"

class NowPlayingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_admin_users = ENV["ADMIN_USERS"]
    @original_admin_user = ENV["ADMIN_USER"]
    @original_plex_token = ENV["PLEX_TOKEN"]
    @original_plex_server_base_url = ENV["PLEX_SERVER_BASE_URL"]
    ENV["ADMIN_USERS"] = "admin@example.com"
    ENV["PLEX_TOKEN"] = "token"
    ENV["PLEX_SERVER_BASE_URL"] = "http://plex.example"
    ENV.delete("ADMIN_USER")
    Rails.cache.clear
    OmniAuth.config.test_mode = true
    sign_in
  end

  teardown do
    ENV["ADMIN_USERS"] = @original_admin_users
    ENV["ADMIN_USER"] = @original_admin_user
    ENV["PLEX_TOKEN"] = @original_plex_token
    ENV["PLEX_SERVER_BASE_URL"] = @original_plex_server_base_url
    Rails.cache.clear
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  test "renders current Plex sessions" do
    client = Class.new do
      def playback_sessions
        [
          {
            title: "The Noise That Blue Makes",
            grandparent_title: "Taskmaster",
            type: "episode",
            library_section_title: "TV Shows",
            duration: "1000",
            view_offset: "500",
            grandparent_thumb: "/library/metadata/1/thumb/123",
            user: { title: "Viewer" },
            player: { title: "Apple TV", platform: "tvOS", state: "playing" },
            session: { id: "session-one" }
          }
        ]
      end
    end.new

    original_from_env = Plex::Client.method(:from_env)
    begin
      Plex::Client.define_singleton_method(:from_env) { client }
      get now_playing_path

      assert_response :success
      assert_select "h1", "Now Playing"
      assert_select "h2", "Taskmaster - The Noise That Blue Makes"
      assert_select "p", "Viewer"
      assert_select "dd", text: "Apple TV · tvOS"
      assert_select "p", text: "50% complete"
      assert_select "img[src*='/plex_cover']"
      assert_select "img[src*='%2Flibrary%2Fmetadata%2F1%2Fthumb%2F123']"
      assert_select "div[data-controller='auto-refresh'][data-auto-refresh-interval-value='10000']"
      assert_select ".flex-1 h2.truncate"
      assert_select "dd.break-all", text: "session-one"
    ensure
      Plex::Client.define_singleton_method(:from_env) { original_from_env.call }
    end
  end

  test "renders sessions partial for background refreshes" do
    client = Class.new do
      def playback_sessions
        [
          {
            title: "Feature",
            type: "movie",
            library_section_title: "Movies",
            duration: "1000",
            view_offset: "250",
            user: { title: "Viewer" },
            player: { title: "Apple TV", platform: "tvOS", state: "playing" },
            session: { id: "session-one" }
          }
        ]
      end
    end.new

    original_from_env = Plex::Client.method(:from_env)
    begin
      Plex::Client.define_singleton_method(:from_env) { client }
      get now_playing_path(partial: 1)

      assert_response :success
      assert_select "h1", false
      assert_select "h2", "Feature"
      assert_select "p", text: "25% complete"
    ensure
      Plex::Client.define_singleton_method(:from_env) { original_from_env.call }
    end
  end

  private

  def sign_in
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      info: {
        email: "admin@example.com",
        name: "Admin User"
      }
    )

    post "/auth/google_oauth2/callback", env: {
      "omniauth.auth" => OmniAuth.config.mock_auth[:google_oauth2]
    }
  end
end
