class CreatePlexNowPlayingSamples < ActiveRecord::Migration[8.1]
  def change
    create_table :plex_now_playing_samples do |t|
      t.string :machine_identifier, null: false
      t.datetime :sampled_at, null: false
      t.string :session_id
      t.string :account_id
      t.string :user_label
      t.string :player_title
      t.string :player_platform
      t.string :ip_address
      t.string :state
      t.string :rating_key
      t.string :media_type
      t.string :title
      t.string :full_title
      t.string :library_title
      t.integer :duration
      t.integer :view_offset
      t.integer :progress_percent
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :plex_now_playing_samples, [ :machine_identifier, :sampled_at ]
    add_index :plex_now_playing_samples, [ :machine_identifier, :account_id, :sampled_at ],
      name: "index_now_playing_samples_on_machine_account_sampled"
  end
end
