class CreatePlexUserNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :plex_user_notes do |t|
      t.string :plex_user_id, null: false
      t.string :username
      t.string :email
      t.text :notes
      t.string :last_edited_by

      t.timestamps
    end

    add_index :plex_user_notes, :plex_user_id, unique: true
  end
end
