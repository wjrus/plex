require "test_helper"

class NowPlayingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_admin_users = ENV["ADMIN_USERS"]
    @original_admin_user = ENV["ADMIN_USER"]
    ENV["ADMIN_USERS"] = "admin@example.com"
    ENV.delete("ADMIN_USER")
    Rails.cache.clear
    OmniAuth.config.test_mode = true
    sign_in
  end

  teardown do
    ENV["ADMIN_USERS"] = @original_admin_users
    ENV["ADMIN_USER"] = @original_admin_user
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
