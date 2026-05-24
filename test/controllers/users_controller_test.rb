require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_machine_identifier = ENV["PLEX_MACHINE_IDENTIFIER"]
    @original_admin_users = ENV["ADMIN_USERS"]
    @original_admin_user = ENV["ADMIN_USER"]
    ENV["PLEX_MACHINE_IDENTIFIER"] = "machine-one"
    ENV["ADMIN_USERS"] = "admin@example.com, wjr@wjr.us"
    ENV.delete("ADMIN_USER")
    OmniAuth.config.test_mode = true
    sign_in
  end

  teardown do
    ENV["PLEX_MACHINE_IDENTIFIER"] = @original_machine_identifier
    ENV["ADMIN_USERS"] = @original_admin_users
    ENV["ADMIN_USER"] = @original_admin_user
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  test "sorts users by name ascending by default" do
    get users_path

    assert_response :success
    assert_select "a[aria-label*='Name, sorted ascending']"
  end

  test "sorts users by last streamed descending" do
    get users_path(sort: "last_streamed", direction: "desc")

    assert_response :success
    assert_select "a[aria-label*='Last Streamed, sorted descending']"
  end

  test "shows user details" do
    get user_path("42")

    assert_response :success
    assert_select "h1", "Viewer"
    assert_select "h2", "Shared Libraries"
    assert_select "textarea[name='plex_user_note[notes]']"
  end

  test "admin can save local notes for a Plex user" do
    patch user_note_path("42"), params: {
      plex_user_note: {
        username: "viewer",
        email: "viewer@example.com",
        notes: "Keep an eye on shared access."
      }
    }

    assert_redirected_to users_path(sort: nil, direction: nil)

    note = PlexUserNote.find_by!(plex_user_id: "42")
    assert_equal "Keep an eye on shared access.", note.notes
    assert_equal "wjr@wjr.us", note.last_edited_by
  end

  private

  def sign_in
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      info: {
        email: "wjr@wjr.us",
        name: "WJR"
      }
    )

    post "/auth/google_oauth2/callback", env: {
      "omniauth.auth" => OmniAuth.config.mock_auth[:google_oauth2]
    }
  end
end
