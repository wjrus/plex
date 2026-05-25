require "test_helper"

class StatsControllerTest < ActionDispatch::IntegrationTest
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

  test "renders playback stats" do
    PlexStreamEvent.create!(
      machine_identifier: "machine-one",
      account_id: "42",
      library_title: "Movies",
      media_type: "movie",
      full_title: "Feature",
      duration: 1000,
      view_offset: 950,
      viewed_at: Time.zone.local(2026, 5, 24, 13, 0, 0)
    )
    PlexStreamEvent.create!(
      machine_identifier: "machine-one",
      account_id: "42",
      library_title: "TV Shows",
      media_type: "episode",
      full_title: "Episode",
      duration: 1000,
      view_offset: 920,
      viewed_at: Time.zone.local(2026, 5, 25, 13, 0, 0)
    )

    get stats_path

    assert_response :success
    assert_select "h1", "Stats"
    assert_select "a[aria-current='page']", "7 days"
    assert_select "a", "30 days"
    assert_select "a", "Past year"
    assert_select "a", "All time"
    assert_select "h2", "Library Activity"
    assert_select "span", text: "Movies"
    assert_select "h2", "Top Users"
    assert_select "h2", "Activity"
  end

  test "filters playback stats by selected period" do
    PlexStreamEvent.create!(
      machine_identifier: "machine-one",
      account_id: "42",
      library_title: "Movies",
      media_type: "movie",
      full_title: "Recent Feature",
      duration: 1000,
      view_offset: 950,
      viewed_at: Time.zone.local(2026, 5, 25, 13, 0, 0)
    )
    PlexStreamEvent.create!(
      machine_identifier: "machine-one",
      account_id: "42",
      library_title: "Movies",
      media_type: "movie",
      full_title: "Older Feature",
      duration: 1000,
      view_offset: 950,
      viewed_at: Time.zone.local(2026, 4, 1, 13, 0, 0)
    )

    get stats_path

    assert_response :success
    assert_select "p", text: "1"

    get stats_path(period: "all")

    assert_response :success
    assert_select "a[aria-current='page']", "All time"
    assert_select "p", text: "2"
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
