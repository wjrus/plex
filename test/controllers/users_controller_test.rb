require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_machine_identifier = ENV["PLEX_MACHINE_IDENTIFIER"]
    @original_admin_users = ENV["ADMIN_USERS"]
    @original_admin_user = ENV["ADMIN_USER"]
    ENV["PLEX_MACHINE_IDENTIFIER"] = "machine-one"
    ENV["ADMIN_USERS"] = "admin@example.com, coadmin@example.com"
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
    assert_select "h2", "Library Access"
    assert_select "input[type=checkbox][name='library_ids[]']"
    assert_select "textarea[name='plex_user_note[notes]']"
    assert_select "button", "Remove user from Plex shares"
  end

  test "filters users by search and notes" do
    get users_path(q: "viewer", notes: "with")

    assert_response :success
    assert_select "td", text: "viewer@example.com"
    assert_select "td", text: /Existing local note/
    assert_select "td", text: /Has notes/
    assert_select "td", text: /1 log event/
    assert_select "textarea[name='plex_user_note[notes]']", count: 0
    assert_select "button", text: "Apply to selected", count: 0
    assert_select "input[name='user_ids[]']", count: 0
    assert_select "tr[role='link'][data-controller='row-link']"
    assert_select "p", text: "1 user shown"
  end

  test "shows empty filtered state" do
    get users_path(q: "not-a-real-user")

    assert_response :success
    assert_select "p", text: "No users match those filters."
  end

  test "highlights pending invites" do
    ShareSnapshot.create!(
      machine_identifier: "machine-one",
      server: { name: "Local Plex" },
      libraries: [ { id: "1", key: "1", title: "Movies", type: "movie" } ],
      users: [
        {
          id: "pending-one",
          title: "Pending Friend",
          username: "pending",
          email: "pending@example.com",
          pending: true,
          library_count: 1,
          libraries: []
        }
      ],
      fetched_at: Time.current
    )

    get users_path

    assert_response :success
    assert_select "h2", "Pending Invites"
    assert_select "p", text: /Pending Friend/
    assert_select "a", text: "View pending"
  end

  test "exports users csv" do
    get users_path(format: :csv)

    assert_response :success
    assert_includes @response.media_type, "text/csv"
    assert_includes @response.body, "name,username,email,status"
    assert_includes @response.body, "Viewer,viewer,viewer@example.com,accepted"
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
    assert_equal "admin@example.com", note.last_edited_by

    log = ShareAuditLog.recent.first
    assert_equal "user_note_updated", log.action
    assert_equal "viewer", log.target_label
    assert_equal "admin@example.com", log.admin_email
    assert_equal "updated notes for viewer", log.summary
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
