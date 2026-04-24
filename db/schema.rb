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

ActiveRecord::Schema[8.1].define(version: 2026_04_24_000000) do
  create_table "trip_requests", force: :cascade do |t|
    t.string "age_group"
    t.string "budget"
    t.integer "child_count", default: 0, null: false
    t.string "companion_pref"
    t.string "contact_type"
    t.datetime "created_at", null: false
    t.integer "custom_days"
    t.string "departure_date", null: false
    t.string "group_identity"
    t.integer "group_size", default: 1, null: false
    t.string "group_type"
    t.string "grouping_pref", null: false
    t.boolean "is_rainbow"
    t.float "match_score"
    t.string "match_type"
    t.datetime "matched_at"
    t.integer "matched_with_id"
    t.text "notes"
    t.string "openid", null: false
    t.string "preferred_age_group"
    t.integer "preferred_total_size"
    t.string "route_mode", null: false
    t.string "selected_route"
    t.string "status", default: "waiting", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "wechat_id", null: false
    t.index ["departure_date"], name: "index_trip_requests_on_departure_date"
    t.index ["matched_with_id"], name: "index_trip_requests_on_matched_with_id"
    t.index ["status"], name: "index_trip_requests_on_status"
    t.index ["user_id"], name: "index_trip_requests_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "openid", null: false
    t.datetime "updated_at", null: false
    t.index ["openid"], name: "index_users_on_openid", unique: true
  end

  add_foreign_key "trip_requests", "users"
end
