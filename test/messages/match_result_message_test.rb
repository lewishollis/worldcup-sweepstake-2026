require "test_helper"

class MatchResultMessageTest < ActiveSupport::TestCase
  setup do
    @friend1 = Friend.create!(name: "Lewis")
    @friend2 = Friend.create!(name: "Jamie")
    @group1 = Group.create!(friend: @friend1, name: "Lewis's Group")
    @group2 = Group.create!(friend: @friend2, name: "Jamie's Group")
    @england = Team.create!(name: "England")
    @france = Team.create!(name: "France")
    @group1.teams << @england
    @group2.teams << @france
  end

  teardown do
    Match.delete_all
    Team.delete_all
    Group.delete_all
    Friend.delete_all
  end

  test "includes team names, score, and friend names" do
    match = Match.create!(
      home_team: @england,
      away_team: @france,
      home_score: 2,
      away_score: 1,
      home_points: 1,
      away_points: 0,
      status: "PostEvent",
      start_time: Time.current,
      match_id: "test-result-1"
    )

    result = MatchResultMessage.call(match)
    assert_includes result, "England"
    assert_includes result, "France"
    assert_includes result, "2"
    assert_includes result, "1"
    assert_includes result, "Lewis"
    assert_includes result, "Jamie"
  end

  test "shows points awarded" do
    match = Match.create!(
      home_team: @england,
      away_team: @france,
      home_score: 2,
      away_score: 1,
      home_points: 1,
      away_points: 0,
      status: "PostEvent",
      start_time: Time.current,
      match_id: "test-result-2"
    )

    result = MatchResultMessage.call(match)
    assert_includes result, "+1 pt"
  end

  test "shows No owner when team has no group" do
    orphan = Team.create!(name: "Brazil")
    match = Match.create!(
      home_team: @england,
      away_team: orphan,
      home_score: 0,
      away_score: 0,
      home_points: 0,
      away_points: 0,
      status: "PostEvent",
      start_time: Time.current,
      match_id: "test-result-3"
    )

    result = MatchResultMessage.call(match)
    assert_includes result, "No owner"
  end
end
