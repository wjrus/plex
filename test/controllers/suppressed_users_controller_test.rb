require "test_helper"

class SuppressedUsersControllerTest < ActionDispatch::IntegrationTest
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

  test "renders suppressed users with latest stream context" do
    PlexUserNote.find_or_initialize_by(plex_user_id: "42").tap do |note|
      note.assign_attributes(
      username: "viewer",
      email: "viewer@example.com",
      notes: "Hidden for now",
      suppressed: true,
      suppressed_at: Time.zone.local(2026, 5, 24, 12, 0, 0),
      suppressed_by: "admin@example.com"
      )
      note.save!
    end
    PlexStreamEvent.create!(
      machine_identifier: "machine-one",
      account_id: "42",
      viewed_at: Time.zone.local(2026, 5, 24, 13, 0, 0),
      full_title: "Feature",
      media_type: "movie"
    )

    get suppressed_users_path

    assert_response :success
    assert_select "h1", "Suppressed Users"
    assert_select "td", text: /viewer/
    assert_select "td", text: /Feature/
    assert_select "form[action='#{user_suppression_path("42")}']"
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
