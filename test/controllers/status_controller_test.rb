require "test_helper"

class StatusControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_admin_users = ENV["ADMIN_USERS"]
    @original_admin_user = ENV["ADMIN_USER"]
    @original_app_revision = ENV["APP_REVISION"]
    @original_git_sha = ENV["GIT_SHA"]
    ENV["ADMIN_USERS"] = "admin@example.com"
    ENV.delete("APP_REVISION")
    ENV.delete("GIT_SHA")
    ENV.delete("ADMIN_USER")
    OmniAuth.config.test_mode = true
    sign_in
  end

  teardown do
    ENV["ADMIN_USERS"] = @original_admin_users
    ENV["ADMIN_USER"] = @original_admin_user
    ENV["APP_REVISION"] = @original_app_revision
    ENV["GIT_SHA"] = @original_git_sha
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  test "renders status page" do
    get status_path

    assert_response :success
    assert_select "h1", "Status"
    assert_select "p", text: "Database"
  end

  test "renders revision from environment" do
    ENV["APP_REVISION"] = "abc1234"

    get status_path

    assert_response :success
    assert_select "p", text: "abc1234"
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
