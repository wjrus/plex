class AddSuppressionToPlexUserNotes < ActiveRecord::Migration[8.1]
  def change
    add_column :plex_user_notes, :suppressed, :boolean, null: false, default: false
    add_column :plex_user_notes, :suppressed_at, :datetime
    add_column :plex_user_notes, :suppressed_by, :string
  end
end
