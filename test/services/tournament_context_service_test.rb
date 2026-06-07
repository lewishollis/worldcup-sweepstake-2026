require "test_helper"

class TournamentContextServiceTest < ActiveSupport::TestCase
  def setup
    @lewis = Friend.create!(name: "Lewis")
    @sarah = Friend.create!(name: "Sarah")
    @lewis_group = Group.create!(name: "Lewis Group", friend: @lewis)
    @sarah_group = Group.create!(name: "Sarah Group", friend: @sarah)
    @brazil = Team.create!(name: "Brazil", flag_url: "https://x.com/b.svg")
    @france = Team.create!(name: "France", flag_url: "https://x.com/f.svg")
    @lewis_group.teams << @brazil
    @sarah_group.teams << @france

    # Brazil earns 3 progression points: qualified (+1) + won Last 16 (+1) + won QF (+1)
    dummy = Team.create!(name: "Dummy_#{SecureRandom.hex(4)}")
    Match.create!(home_team: @brazil, away_team: dummy,
                  home_score: 2, away_score: 0, winner: "home",
                  status: "PostEvent", stage: "Last 16",
                  start_time: 1.day.ago, match_id: "ctx-brazil-1")
    Match.create!(home_team: @brazil, away_team: dummy,
                  home_score: 1, away_score: 0, winner: "home",
                  status: "PostEvent", stage: "Quarter-finals",
                  start_time: 1.day.ago, match_id: "ctx-brazil-2")

    # France earns 1 progression point: qualified (+1) but lost
    Match.create!(home_team: @france, away_team: dummy,
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

  test "leaderboard includes teams array for each entry" do
    lb = TournamentContextService.new.leaderboard
    assert_includes lb.first[:teams], "Brazil"
    assert_includes lb.last[:teams], "France"
  end

  test "leaderboard_text includes tournament status header" do
    text = TournamentContextService.new.leaderboard_text
    assert_includes text, "TOURNAMENT STATUS:"
  end

  test "tournament_status returns not_started when no matches exist" do
    Match.destroy_all
    assert_equal :not_started, TournamentContextService.new.tournament_status
  end

  test "tournament_status returns knockout_stage when knockout matches exist" do
    # setup already creates Last 16 PostEvent matches
    assert_equal :knockout_stage, TournamentContextService.new.tournament_status
  end

  test "tournament_status returns group_stage when only group stage matches exist" do
    Match.destroy_all
    Match.create!(home_team: @brazil, away_team: @france, stage: "Group Stage",
                  status: "PostEvent", match_id: "gs-test", home_score: 1, away_score: 0,
                  winner: "home", start_time: 1.day.ago)
    assert_equal :group_stage, TournamentContextService.new.tournament_status
  end

  test "tournament_status returns complete when Final is PostEvent" do
    Match.create!(home_team: @brazil, away_team: @france, stage: "Final",
                  status: "PostEvent", match_id: "final-test", home_score: 1, away_score: 0,
                  winner: "home", start_time: Time.current)
    assert_equal :complete, TournamentContextService.new.tournament_status
  end

  test "champion returns nil when tournament not complete" do
    assert_nil TournamentContextService.new.champion
  end

  test "champion returns team name and owner name when Final is PostEvent" do
    Match.create!(home_team: @brazil, away_team: @france, stage: "Final",
                  status: "PostEvent", match_id: "final-champ", home_score: 1, away_score: 0,
                  winner: "home", start_time: Time.current)
    champ = TournamentContextService.new.champion
    assert_equal "Brazil", champ[:team]
    assert_equal "Lewis", champ[:owner]
  end

  test "champion returns away team name and owner when away team wins Final" do
    Match.create!(home_team: @brazil, away_team: @france, stage: "Final",
                  status: "PostEvent", match_id: "final-away-win", home_score: 0, away_score: 1,
                  winner: "away", start_time: Time.current)
    champ = TournamentContextService.new.champion
    assert_equal "France", champ[:team]
    assert_equal "Sarah", champ[:owner]
  end

  test "leaderboard_text includes champion when tournament complete" do
    Match.create!(home_team: @brazil, away_team: @france, stage: "Final",
                  status: "PostEvent", match_id: "final-text", home_score: 1, away_score: 0,
                  winner: "home", start_time: Time.current)
    text = TournamentContextService.new.leaderboard_text
    assert_includes text, "CHAMPION:"
    assert_includes text, "Brazil"
  end
end
