require "test_helper"

class SharesControllerTest < ActionDispatch::IntegrationTest
  FakeClient = Struct.new(:removed_share_id, :created_invite) do
    def create_shared_server(_machine_identifier, invited_email, library_section_ids, allow_sync: false)
      self.created_invite = {
        invited_email: invited_email,
        library_section_ids: library_section_ids,
        allow_sync: allow_sync
      }
    end

    def remove_shared_server(_machine_identifier, shared_server_id)
      self.removed_share_id = shared_server_id
    end

    def server(_machine_identifier)
      {
        server: { name: "Local Plex" },
        sections: [ { id: "1", key: "1", title: "Movies", type: "movie" } ]
      }
    end

    def shared_servers(_machine_identifier)
      []
    end

    def users
      []
    end
  end

  setup do
    @original_machine_identifier = ENV["PLEX_MACHINE_IDENTIFIER"]
    @original_admin_users = ENV["ADMIN_USERS"]
    @original_admin_user = ENV["ADMIN_USER"]
    ENV["PLEX_MACHINE_IDENTIFIER"] = "machine-one"
    ENV["ADMIN_USERS"] = "wjr@wjr.us"
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

  test "shares page renders library checkbox pills" do
    get root_path

    assert_response :success
    assert_select "input[type=checkbox][name='library_ids[]']"
    assert_select "select[name='library_ids[]']", count: 0
  end

  test "admin can invite a user to selected libraries" do
    client = FakeClient.new
    with_plex_client(client) do
      post shares_path, params: {
        invited_email: "friend@example.com",
        library_ids: [ "1" ],
        allow_sync: "1"
      }
    end

    assert_redirected_to root_path
    assert_equal(
      {
        invited_email: "friend@example.com",
        library_section_ids: [ "1" ],
        allow_sync: true
      },
      client.created_invite
    )
  end

  test "admin can remove a share" do
    client = FakeClient.new
    with_plex_client(client) { delete share_path("99") }

    assert_redirected_to root_path
    assert_equal "99", client.removed_share_id
    assert_empty ShareSnapshot.latest_for("machine-one").users
  end

  private

  def with_plex_client(client)
    original_from_env = Plex::Client.method(:from_env)
    Plex::Client.define_singleton_method(:from_env) { client }
    yield
  ensure
    Plex::Client.define_singleton_method(:from_env, original_from_env)
  end

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
