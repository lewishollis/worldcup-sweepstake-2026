require "test_helper"

class ScenarioEngineTest < ActiveSupport::TestCase
  def setup
    @lewis  = Friend.create!(name: "Lewis")
    @sarah  = Friend.create!(name: "Sarah")
    @lewis_group = Group.create!(name: "Lewis Group", friend: @lewis)
    @sarah_group = Group.create!(name: "Sarah Group", friend: @sarah)
    @brazil = Team.create!(name: "Brazil", flag_url: "https://x.com/b.svg")
    @france = Team.create!(name: "France", flag_url: "https://x.com/f.svg")
    @lewis_group.teams << @brazil
    @sarah_group.teams << @france

    # Give Brazil 2 progression points via a won knockout match
    dummy_opponent = Team.create!(name: "Dummy_#{SecureRandom.hex(4)}")
    Match.create!(home_team: @brazil, away_team: dummy_opponent,
                  home_score: 2, away_score: 0, winner: "home",
                  status: "PostEvent", stage: "Last 16",
                  start_time: 1.day.ago, match_id: "setup-brazil-1")
    # Give France 1 progression point (qualified but lost)
    Match.create!(home_team: @france, away_team: dummy_opponent,
                  home_score: 0, away_score: 1, winner: "away",
                  status: "PostEvent", stage: "Last 16",
                  start_time: 1.day.ago, match_id: "setup-france-1")
  end

  test "knockout match returns home_win and away_win scenarios only" do
    match = Match.create!(
      home_team: @brazil, away_team: @france,
      stage: "Last 16", status: "PreEvent",
      match_id: "test-1", home_score: 0, away_score: 0
    )
    result = ScenarioEngine.new(match).call
    assert_equal [:home_win, :away_win], result.keys
  end

  test "group stage match returns home_win, draw, and away_win scenarios" do
    match = Match.create!(
      home_team: @brazil, away_team: @france,
      stage: "Group Stage", status: "PreEvent",
      match_id: "test-2", home_score: 0, away_score: 0
    )
    result = ScenarioEngine.new(match).call
    assert_equal [:home_win, :draw, :away_win], result.keys
  end

  test "Last 16 home win awards 1 point to home team" do
    match = Match.create!(
      home_team: @brazil, away_team: @france,
      stage: "Last 16", status: "PreEvent",
      match_id: "test-3", home_score: 0, away_score: 0
    )
    result = ScenarioEngine.new(match).call
    home_win = result[:home_win]
    assert_equal 1, home_win[:team_points].length
    assert_equal "Brazil", home_win[:team_points].first[:team_name]
    assert_equal 1, home_win[:team_points].first[:points_awarded]
    assert_equal "Last 16 win", home_win[:team_points].first[:reason]
  end

  test "Last 16 home win adds delta to Lewis who owns Brazil" do
    match = Match.create!(
      home_team: @brazil, away_team: @france,
      stage: "Last 16", status: "PreEvent",
      match_id: "test-4", home_score: 0, away_score: 0
    )
    result = ScenarioEngine.new(match).call
    home_win = result[:home_win]
    lewis_delta = home_win[:friend_deltas].find { |d| d[:friend] == "Lewis" }
    # Brazil earns +1 pt, no multiplier → +1 to Lewis's group score
    assert_equal 1.0, lewis_delta[:delta]
    assert_equal @lewis_group.total_points + 1.0, lewis_delta[:new_total]
  end

  test "Last 16 home win updates rank changes correctly" do
    # Lewis currently leads (Brazil 2pts vs France 1pt)
    match = Match.create!(
      home_team: @brazil, away_team: @france,
      stage: "Last 16", status: "PreEvent",
      match_id: "test-5", home_score: 0, away_score: 0
    )
    result = ScenarioEngine.new(match).call
    home_win = result[:home_win]
    assert_equal "Lewis", home_win[:new_leader]
  end

  test "Final home win awards 2 points to winner and 1 to runner-up" do
    match = Match.create!(
      home_team: @brazil, away_team: @france,
      stage: "Final", status: "PreEvent",
      match_id: "test-6", home_score: 0, away_score: 0
    )
    result = ScenarioEngine.new(match).call
    home_win = result[:home_win]
    brazil_pts = home_win[:team_points].find { |t| t[:team_name] == "Brazil" }
    france_pts = home_win[:team_points].find { |t| t[:team_name] == "France" }
    assert_equal 2, brazil_pts[:points_awarded]
    assert_equal 1, france_pts[:points_awarded]
    assert_equal "Final winner", brazil_pts[:reason]
    assert_equal "Final runner-up", france_pts[:reason]
  end

  test "Group Stage outcomes award zero points" do
    match = Match.create!(
      home_team: @brazil, away_team: @france,
      stage: "Group Stage", status: "PreEvent",
      match_id: "test-7", home_score: 0, away_score: 0
    )
    result = ScenarioEngine.new(match).call
    [:home_win, :draw, :away_win].each do |outcome|
      assert_empty result[outcome][:team_points]
      assert_empty result[outcome][:friend_deltas]
    end
  end

  test "rank changes detected when outcome flips leaderboard position" do
    # Give France more wins so Sarah leads: create additional match wins for France
    dummy2 = Team.create!(name: "Dummy2_#{SecureRandom.hex(4)}")
    # France wins 4 more knockout matches to get score of 5
    4.times do |i|
      Match.create!(home_team: @france, away_team: dummy2,
                    home_score: 1, away_score: 0, winner: "home",
                    status: "PostEvent", stage: "Quarter-finals",
                    start_time: 1.day.ago, match_id: "sarah-wins-#{i}-#{SecureRandom.hex(4)}")
    end
    # Now Sarah (France) has 5 progression points; Lewis (Brazil) has 2
    match = Match.create!(
      home_team: @brazil, away_team: @france,
      stage: "Semi-finals", status: "PreEvent",
      match_id: "test-8", home_score: 0, away_score: 0
    )
    result = ScenarioEngine.new(match).call
    home_win = result[:home_win] # Brazil wins → Lewis gets +1
    lewis_rank = home_win[:rank_changes].find { |r| r[:friend] == "Lewis" }
    # Lewis was rank 2, after +1 still behind Sarah (5 vs 3), no rank change
    assert_nil lewis_rank

    # France wins: Sarah gets +1, stays leader
    away_win = result[:away_win]
    assert_equal "Sarah", away_win[:new_leader]
  end
end
