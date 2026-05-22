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
end
