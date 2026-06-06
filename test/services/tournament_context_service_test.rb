require "test_helper"

class TournamentContextServiceTest < ActiveSupport::TestCase
  def setup
    @lewis = Friend.create!(name: "Lewis")
    @sarah = Friend.create!(name: "Sarah")
    @lewis_group = Group.create!(name: "Lewis Group", friend: @lewis)
    @sarah_group = Group.create!(name: "Sarah Group", friend: @sarah)
    brazil = Team.create!(name: "Brazil", flag_url: "https://x.com/b.svg")
    france = Team.create!(name: "France", flag_url: "https://x.com/f.svg")
    @lewis_group.teams << brazil
    @sarah_group.teams << france

    # Brazil earns 3 progression points: qualified (+1) + won Last 16 (+1) + won QF (+1)
    dummy = Team.create!(name: "Dummy_#{SecureRandom.hex(4)}")
    Match.create!(home_team: brazil, away_team: dummy,
                  home_score: 2, away_score: 0, winner: "home",
                  status: "PostEvent", stage: "Last 16",
                  start_time: 1.day.ago, match_id: "ctx-brazil-1")
    Match.create!(home_team: brazil, away_team: dummy,
                  home_score: 1, away_score: 0, winner: "home",
                  status: "PostEvent", stage: "Quarter-finals",
                  start_time: 1.day.ago, match_id: "ctx-brazil-2")

    # France earns 1 progression point: qualified (+1) but lost
    Match.create!(home_team: france, away_team: dummy,
                  home_score: 0, away_score: 1, winner: "away",
                  status: "PostEvent", stage: "Last 16",
                  start_time: 1.day.ago, match_id: "ctx-france-1")
  end

  test "leaderboard returns friends ranked by score descending" do
    ctx = TournamentContextService.new
    lb = ctx.leaderboard
    assert_equal "Lewis", lb.first[:friend]   # Brazil: 3pts
    assert_equal "Sarah", lb.last[:friend]    # France: 1pt
    assert_equal 3.0, lb.first[:score]
    assert_equal 1.0, lb.last[:score]
  end

  test "leaderboard includes rank" do
    ctx = TournamentContextService.new
    lb = ctx.leaderboard
    assert_equal 1, lb.first[:rank]
    assert_equal 2, lb.last[:rank]
  end

  test "leaderboard_text formats standings as readable string" do
    ctx = TournamentContextService.new
    text = ctx.leaderboard_text
    assert_includes text, "1. Lewis"
    assert_includes text, "2. Sarah"
  end

  test "news_items returns empty array when no news exists" do
    ctx = TournamentContextService.new
    assert_equal [], ctx.news_items(limit: 3)
  end
end
