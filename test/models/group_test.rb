require "test_helper"

class GroupTest < ActiveSupport::TestCase
  setup do
    @friend = Friend.create!(name: "Test Friend")
    @group = Group.create!(name: "Test Group", friend: @friend)
    @team1 = Team.create!(name: "Brazil", flag_url: "https://example.com/br.svg")
    @team2 = Team.create!(name: "France", flag_url: "https://example.com/fr.svg")
    @opponent = Team.create!(name: "Germany", flag_url: "https://example.com/de.svg")
    @group.teams << [@team1, @team2]
  end

  test "total_points is 0 when no teams have reached the knockouts" do
    assert_equal 0.0, @group.total_points
  end

  test "total_points sums progression scores across teams" do
    # team1 knocked out in Last 32 → 1.0
    Match.create!(home_team: @team1, away_team: @opponent, stage: "Last 32",
                  status: "PostEvent", winner: "away", match_id: "r32-t1",
                  start_time: 1.day.ago)
    # team2 wins Last 32, loses Last 16 → 2.0
    Match.create!(home_team: @team2, away_team: @opponent, stage: "Last 32",
                  status: "PostEvent", winner: "home", match_id: "r32-t2",
                  start_time: 1.day.ago)
    Match.create!(home_team: @team2, away_team: @opponent, stage: "Last 16",
                  status: "PostEvent", winner: "away", match_id: "r16-t2",
                  start_time: 12.hours.ago)

    assert_equal 3.0, @group.total_points
  end

  test "total_points is 0 when teams have only played group stage matches" do
    Match.create!(home_team: @team1, away_team: @opponent, stage: "Group Stage",
                  status: "PostEvent", winner: "home", match_id: "gs-1",
                  start_time: 1.day.ago)
    assert_equal 0.0, @group.total_points
  end
end
