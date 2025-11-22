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

ActiveRecord::Schema[7.0].define(version: 2024_06_23_194848) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "friend_group_teams", force: :cascade do |t|
    t.bigint "friends_group_id"
    t.bigint "team_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["friends_group_id"], name: "index_friend_group_teams_on_friends_group_id"
    t.index ["team_id"], name: "index_friend_group_teams_on_team_id"
  end

  create_table "friends", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "group_id"
    t.string "profile_picture_url"
    t.index ["group_id"], name: "index_friends_on_group_id"
  end

  create_table "friends_groups", force: :cascade do |t|
    t.string "name"
    t.bigint "friend_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["friend_id"], name: "index_friends_groups_on_friend_id"
  end

  create_table "groups", force: :cascade do |t|
    t.bigint "friend_id"
    t.string "name"
    t.float "multiplier", default: 1.0
    t.float "score", default: 0.0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "total_points"
    t.index ["friend_id"], name: "index_groups_on_friend_id"
  end

  create_table "groups_teams", force: :cascade do |t|
    t.bigint "group_id"
    t.bigint "team_id"
    t.index ["group_id"], name: "index_groups_teams_on_group_id"
    t.index ["team_id"], name: "index_groups_teams_on_team_id"
  end

  create_table "matches", force: :cascade do |t|
    t.bigint "home_team_id", null: false
    t.bigint "away_team_id", null: false
    t.integer "home_score"
    t.integer "away_score"
    t.datetime "start_time", precision: nil
    t.string "status"
    t.string "winner"
    t.string "accessible_event_summary"
    t.integer "home_points", default: 0
    t.integer "away_points", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "stage"
    t.string "match_id"
    t.string "home_friend_profile_picture_url"
    t.string "away_friend_profile_picture_url"
    t.bigint "team_id"
    t.string "result"
    t.index ["away_team_id"], name: "index_matches_on_away_team_id"
    t.index ["home_team_id"], name: "index_matches_on_home_team_id"
    t.index ["match_id"], name: "index_matches_on_match_id"
    t.index ["team_id"], name: "index_matches_on_team_id"
  end

  create_table "sets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "teams", force: :cascade do |t|
    t.string "name"
    t.integer "points", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "progressed"
    t.bigint "friends_id"
    t.string "flag_url"
    t.index ["friends_id"], name: "index_teams_on_friends_id"
  end

  add_foreign_key "friend_group_teams", "friends_groups"
  add_foreign_key "friend_group_teams", "teams"
  add_foreign_key "friends", "groups"
  add_foreign_key "friends_groups", "friends"
  add_foreign_key "groups", "friends"
  add_foreign_key "matches", "teams"
  add_foreign_key "matches", "teams", column: "away_team_id"
  add_foreign_key "matches", "teams", column: "home_team_id"
  add_foreign_key "teams", "friends", column: "friends_id"
end
