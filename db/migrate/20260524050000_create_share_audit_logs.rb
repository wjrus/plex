class CreateShareAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :share_audit_logs do |t|
      t.string :action, null: false
      t.string :admin_email, null: false
      t.string :plex_user_id
      t.string :share_id
      t.string :target_label
      t.string :target_email
      t.jsonb :libraries_added, null: false, default: []
      t.jsonb :libraries_removed, null: false, default: []
      t.jsonb :libraries_after, null: false, default: []
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :share_audit_logs, :created_at
    add_index :share_audit_logs, :admin_email
    add_index :share_audit_logs, :plex_user_id
    add_index :share_audit_logs, :share_id
  end
end
