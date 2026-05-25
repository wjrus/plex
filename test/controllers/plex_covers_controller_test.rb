require "test_helper"

class PlexCoversControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_admin_users = ENV["ADMIN_USERS"]
    @original_admin_user = ENV["ADMIN_USER"]
    @original_plex_token = ENV["PLEX_TOKEN"]
    @original_plex_server_base_url = ENV["PLEX_SERVER_BASE_URL"]
    ENV["ADMIN_USERS"] = "admin@example.com"
    ENV["PLEX_TOKEN"] = "token"
    ENV["PLEX_SERVER_BASE_URL"] = "http://plex.example:32400"
    ENV.delete("ADMIN_USER")
    OmniAuth.config.test_mode = true
    sign_in
  end

  teardown do
    ENV["ADMIN_USERS"] = @original_admin_users
    ENV["ADMIN_USER"] = @original_admin_user
    ENV["PLEX_TOKEN"] = @original_plex_token
    ENV["PLEX_SERVER_BASE_URL"] = @original_plex_server_base_url
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  test "proxies Plex cover art through the Rails app" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response["Content-Type"] = "image/jpeg"
    response.instance_variable_set(:@body, "jpeg-bytes")
    response.instance_variable_set(:@read, true)
    fake_http = Class.new do
      define_method(:request) do |request|
        raise "missing Plex token" unless request.uri.query.include?("X-Plex-Token=token")
        raise "wrong cover path" unless request.uri.path == "/library/metadata/1/thumb/123"

        response
      end
    end.new

    original_start = Net::HTTP.method(:start)
    begin
      Net::HTTP.define_singleton_method(:start) do |*args, **kwargs, &block|
        block.call(fake_http)
      end

      get plex_cover_path(path: "/library/metadata/1/thumb/123")

      assert_response :success
      assert_equal "image/jpeg", @response.media_type
      assert_equal "jpeg-bytes", @response.body
    ensure
      Net::HTTP.define_singleton_method(:start) do |*args, **kwargs, &block|
        original_start.call(*args, **kwargs, &block)
      end
    end
  end

  test "rejects unsupported cover paths" do
    get plex_cover_path(path: "/status/sessions")

    assert_response :not_found
  end

  test "rejects svg cover responses" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response["Content-Type"] = "image/svg+xml"
    response.instance_variable_set(:@body, "<svg></svg>")
    response.instance_variable_set(:@read, true)
    fake_http = Class.new do
      define_method(:request) { |_request| response }
    end.new

    original_start = Net::HTTP.method(:start)
    begin
      Net::HTTP.define_singleton_method(:start) do |*args, **kwargs, &block|
        block.call(fake_http)
      end

      get plex_cover_path(path: "/library/metadata/1/thumb/123")

      assert_response :not_found
    ensure
      Net::HTTP.define_singleton_method(:start) do |*args, **kwargs, &block|
        original_start.call(*args, **kwargs, &block)
      end
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
