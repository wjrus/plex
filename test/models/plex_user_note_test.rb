require "test_helper"

class PlexUserNoteTest < ActiveSupport::TestCase
  test "requires a Plex user id" do
    note = PlexUserNote.new

    assert_not note.valid?
    assert_includes note.errors[:plex_user_id], "can't be blank"
  end

  test "indexes notes by Plex user id" do
    notes = PlexUserNote.for_users([
      Plex::SharingReport::SharedUser.new(
        id: "42",
        share_id: nil,
        title: "Viewer",
        username: "viewer",
        email: "viewer@example.com",
        thumb: nil,
        home: false,
        restricted: false,
        allow_sync: false,
        allow_channels: false,
        last_seen_at: nil,
        last_streamed_at: nil,
        last_streamed_title: nil,
        last_streamed_type: nil,
        invited_at: nil,
        invite_friend: nil,
        invite_server: nil,
        pending: false,
        all_libraries: false,
        library_count: 0,
        libraries: []
      )
    ])

    assert_equal plex_user_notes(:one), notes["42"]
  end
end
