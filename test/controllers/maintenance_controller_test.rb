require "test_helper"

class MaintenanceControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_admin_users = ENV["ADMIN_USERS"]
    @original_machine_identifier = ENV["PLEX_MACHINE_IDENTIFIER"]
    ENV["ADMIN_USERS"] = "admin@example.com"
    ENV["PLEX_MACHINE_IDENTIFIER"] = "machine-one"
    OmniAuth.config.test_mode = true
    sign_in
  end

  teardown do
    ENV["ADMIN_USERS"] = @original_admin_users
    ENV["PLEX_MACHINE_IDENTIFIER"] = @original_machine_identifier
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  test "renders maintenance page" do
    PlexNowPlayingSample.create!(
      machine_identifier: "machine-one",
      sampled_at: Time.zone.local(2026, 5, 25, 12, 0, 0),
      session_id: "session-one"
    )

    get maintenance_path

    assert_response :success
    assert_select "h1", "Maintenance"
    assert_select "h2", "Plex Data Refresh"
    assert_select "form[action='#{refresh_shares_path}']"
    assert_select "input[type=checkbox][name='include_history']"
    assert_select "h2", "Now Playing Samples"
    assert_select "form[action='#{maintenance_sample_now_playing_path}']"
    assert_select "form[action='#{maintenance_prune_now_playing_samples_path}']"
  end

  test "renders refresh panel partial" do
    RefreshRun.create!(
      machine_identifier: "machine-one",
      status: "running",
      admin_email: "admin@example.com",
      include_history: true,
      started_at: Time.current,
      last_message: "History page 4 retrieved",
      history_pages_retrieved: 4,
      history_rows_retrieved: 4000
    )

    get maintenance_refresh_path

    assert_response :success
    assert_select "h2", "Plex Data Refresh"
    assert_select "dd", text: "History page 4 retrieved"
    assert_select "[data-controller='auto-refresh']"
  end

  test "prunes now playing samples" do
    PlexNowPlayingSample.create!(
      machine_identifier: "machine-one",
      sampled_at: 91.days.ago,
      session_id: "old"
    )

    assert_difference -> { PlexNowPlayingSample.count }, -1 do
      post maintenance_prune_now_playing_samples_path
    end
    assert_redirected_to maintenance_path
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
