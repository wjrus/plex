require "test_helper"

class ShareAuditLogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_admin_users = ENV["ADMIN_USERS"]
    @original_admin_user = ENV["ADMIN_USER"]
    ENV["ADMIN_USERS"] = "admin@example.com"
    ENV.delete("ADMIN_USER")
    OmniAuth.config.test_mode = true
    sign_in
  end

  teardown do
    ENV["ADMIN_USERS"] = @original_admin_users
    ENV["ADMIN_USER"] = @original_admin_user
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  test "renders audit log entries" do
    get share_audit_logs_path

    assert_response :success
    assert_select "h1", "Log"
    assert_select "td", text: "admin@example.com"
    assert_select "td", text: /added Movies to Viewer/
  end

  test "filters audit log entries" do
    get share_audit_logs_path(action_type: "libraries_added", q: "Viewer")

    assert_response :success
    assert_select "td", text: /added Movies to Viewer/
  end

  test "exports audit log csv" do
    get share_audit_logs_path(format: :csv)

    assert_response :success
    assert_includes response.media_type, "text/csv"
    assert_includes response.body, "created_at,admin_email,action"
    assert_includes response.body, "libraries_added"
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
