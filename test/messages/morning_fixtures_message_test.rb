require "test_helper"

class MorningFixturesMessageTest < ActiveSupport::TestCase
  setup do
    # Create minimal DB objects for each test
    @friend1 = Friend.create!(name: "Alice")
    @friend2 = Friend.create!(name: "Bob")
    @group1 = Group.create!(friend: @friend1, name: "Alice's Group")
    @group2 = Group.create!(friend: @friend2, name: "Bob's Group")
    @brazil = Team.create!(name: "Brazil")
    @argentina = Team.create!(name: "Argentina")
    @group1.teams << @brazil
    @group2.teams << @argentina
  end

  teardown do
    WhatsappNotification.delete_all
    Match.delete_all
    Team.delete_all
    Group.delete_all
    Friend.delete_all
  end

  test "returns nil when no matches today" do
    assert_nil MorningFixturesMessage.call(Date.today)
  end

  test "includes team names and friend names for today's matches" do
    Match.create!(
      home_team: @brazil,
      away_team: @argentina,
      start_time: Date.today.to_time + 15.hours,
      status: "PreEvent",
      match_id: "test-morning-1"
    )

    result = MorningFixturesMessage.call(Date.today)
    assert_not_nil result
    assert_includes result, "Brazil"
    assert_includes result, "Argentina"
    assert_includes result, "Alice"
    assert_includes result, "Bob"
  end

  test "excludes matches on other days" do
    Match.create!(
      home_team: @brazil,
      away_team: @argentina,
      start_time: Date.tomorrow.to_time + 15.hours,
      status: "PreEvent",
      match_id: "test-morning-2"
    )

    assert_nil MorningFixturesMessage.call(Date.today)
  end

  test "excludes PostEvent matches" do
    Match.create!(
      home_team: @brazil,
      away_team: @argentina,
      start_time: Date.today.to_time + 15.hours,
      status: "PostEvent",
      match_id: "test-morning-3"
    )

    assert_nil MorningFixturesMessage.call(Date.today)
  end

  test "shows No owner when team has no group" do
    orphan = Team.create!(name: "France")
    Match.create!(
      home_team: @brazil,
      away_team: orphan,
      start_time: Date.today.to_time + 15.hours,
      status: "PreEvent",
      match_id: "test-morning-4"
    )

    result = MorningFixturesMessage.call(Date.today)
    assert_includes result, "No owner"
  end
end
