# test/models/game_score_test.rb
require "test_helper"

class GameScoreTest < ActiveSupport::TestCase
  setup do
    @friend = Friend.create!(name: "Lewis")
  end

  test "valid with friend and streak" do
    score = GameScore.new(friend: @friend, streak: 5)
    assert score.valid?
  end

  test "valid with streak of zero" do
    score = GameScore.new(friend: @friend, streak: 0)
    assert score.valid?
  end

  test "invalid without friend" do
    score = GameScore.new(streak: 5)
    assert_not score.valid?
    assert_includes score.errors[:friend], "must exist"
  end

  test "invalid without streak" do
    score = GameScore.new(friend: @friend)
    assert_not score.valid?
    assert_includes score.errors[:streak], "can't be blank"
  end

  test "invalid with negative streak" do
    score = GameScore.new(friend: @friend, streak: -1)
    assert_not score.valid?
    assert_includes score.errors[:streak], "must be greater than or equal to 0"
  end

  test "best_per_friend returns max streak per friend ordered descending" do
    friend2 = Friend.create!(name: "Ben")
    GameScore.create!(friend: @friend, streak: 12)
    GameScore.create!(friend: @friend, streak: 7)   # lower — should not appear
    GameScore.create!(friend: friend2, streak: 9)

    results = GameScore.best_per_friend
    assert_equal 2, results.length
    assert_equal 12, results.first[:best_streak]
    assert_equal @friend.id, results.first[:friend_id]
    assert_equal 9, results.second[:best_streak]
  end

  test "best_per_friend tie-breaks by earliest first_achieved" do
    friend2 = Friend.create!(name: "Aimee")
    GameScore.create!(friend: @friend, streak: 10, created_at: 2.days.ago)
    GameScore.create!(friend: friend2, streak: 10, created_at: 1.day.ago)

    results = GameScore.best_per_friend
    assert_equal @friend.id, results.first[:friend_id]
  end

  test "locked? is false before the deadline and true after" do
    assert_not GameScore.locked?(GameScore::DEADLINE - 1.minute)
    assert GameScore.locked?(GameScore::DEADLINE + 1.minute)
  end

  test "suspicious_devices flags a device that scored for more than one friend" do
    friend2 = Friend.create!(name: "Ella")
    friend3 = Friend.create!(name: "Sam")
    # Sam's phone scores for himself and for Ella
    GameScore.create!(friend: friend3, streak: 4, device_id: "sam-phone")
    GameScore.create!(friend: friend2, streak: 6, device_id: "sam-phone")
    # A clean device scoring only for one friend
    GameScore.create!(friend: @friend, streak: 3, device_id: "lewis-phone")
    # Legacy rows with no device_id are ignored
    GameScore.create!(friend: @friend, streak: 8, device_id: nil)

    flags = GameScore.suspicious_devices
    assert_equal ["sam-phone"], flags.keys
    assert_equal ["Ella", "Sam"], flags["sam-phone"]
  end

  test "device_summary lists every device with plays and flags multi-friend ones" do
    friend2 = Friend.create!(name: "Ella")
    GameScore.create!(friend: friend2, streak: 6, device_id: "sam-phone")
    GameScore.create!(friend: @friend, streak: 4, device_id: "sam-phone")
    GameScore.create!(friend: @friend, streak: 3, device_id: "lewis-phone")
    GameScore.create!(friend: @friend, streak: 9, device_id: nil) # legacy, ignored

    summary = GameScore.device_summary
    assert_equal ["sam-phone", "lewis-phone"], summary.map { |d| d[:device_id] } # flagged first

    sam = summary.find { |d| d[:device_id] == "sam-phone" }
    assert sam[:suspicious?]
    assert_equal 2, sam[:plays]
    assert_equal ["Ella", "Lewis"], sam[:friend_names]

    lewis = summary.find { |d| d[:device_id] == "lewis-phone" }
    assert_not lewis[:suspicious?]
    assert_equal 1, lewis[:plays]
  end
end
