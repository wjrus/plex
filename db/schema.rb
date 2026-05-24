# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_24_032352) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "plex_user_notes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "last_edited_by"
    t.text "notes"
    t.string "plex_user_id", null: false
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["plex_user_id"], name: "index_plex_user_notes_on_plex_user_id", unique: true
  end

  create_table "share_snapshots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "fetched_at", null: false
    t.jsonb "libraries", default: [], null: false
    t.string "machine_identifier", null: false
    t.jsonb "server", default: {}, null: false
    t.datetime "updated_at", null: false
    t.jsonb "users", default: [], null: false
    t.index ["machine_identifier", "fetched_at"], name: "index_share_snapshots_on_machine_identifier_and_fetched_at"
  end
end
