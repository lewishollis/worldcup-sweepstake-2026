require "test_helper"

class GroupTest < ActiveSupport::TestCase
  test "total_points should multiply team points by multiplier" do
    # Create a group with multiplier 3
    friend = Friend.create!(name: "Test Friend")
    group = Group.create!(name: "Test Group", multiplier: 3.0, friend: friend)

    # Create teams with points
    team1 = Team.create!(name: "Team 1", flag_url: "https://example.com/flag1.svg", points: 2, progressed: true)
    team2 = Team.create!(name: "Team 2", flag_url: "https://example.com/flag2.svg", points: 4, progressed: true)

    group.teams << [team1, team2]

    # Total should be (2 + 4) * 3 = 18
    assert_equal 18, group.total_points
  end

  test "total_points should handle teams with no points" do
    friend = Friend.create!(name: "Test Friend")
    group = Group.create!(name: "Test Group", multiplier: 2.0, friend: friend)

    team = Team.create!(name: "Team 1", flag_url: "https://example.com/flag1.svg", points: 0)
    group.teams << team

    assert_equal 0, group.total_points
  end

  test "total_points should not double count progression points" do
    friend = Friend.create!(name: "Test Friend")
    group = Group.create!(name: "Test Group", multiplier: 1.0, friend: friend)

    # Team with 1 point for progression (already in team.points)
    team = Team.create!(name: "Team 1", flag_url: "https://example.com/flag1.svg", points: 1, progressed: true)
    group.teams << team

    # Should be 1 * 1 = 1, not 2 (which would happen if we added progression again)
    assert_equal 1, group.total_points
  end

  test "total_points should work with different multipliers" do
    friend = Friend.create!(name: "Test Friend")
    group = Group.create!(name: "Test Group", multiplier: 5.0, friend: friend)

    team1 = Team.create!(name: "Team 1", flag_url: "https://example.com/flag1.svg", points: 6, progressed: true)
    team2 = Team.create!(name: "Team 2", flag_url: "https://example.com/flag2.svg", points: 0)

    group.teams << [team1, team2]

    # Total should be (6 + 0) * 5 = 30
    assert_equal 30, group.total_points
  end
end
