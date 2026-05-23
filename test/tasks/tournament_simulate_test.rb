require "test_helper"
require "rake"
require Rails.root.join("lib", "tournament_simulation")

class TournamentSimulateTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks
  end

  teardown do
    Match.delete_all
    Team.delete_all
    Group.delete_all
    Friend.delete_all
    AiInsightCache.delete_all
    Rake::Task["tournament:simulate"].reenable if Rake::Task.task_defined?("tournament:simulate")
  end

  # ── calculate_standings ──────────────────────────────────────────────────

  test "calculate_standings sorts teams by points" do
    t1 = Team.create!(name: "Alpha_#{SecureRandom.hex(4)}")
    t2 = Team.create!(name: "Beta_#{SecureRandom.hex(4)}")
    t3 = Team.create!(name: "Gamma_#{SecureRandom.hex(4)}")
    t4 = Team.create!(name: "Delta_#{SecureRandom.hex(4)}")

    # t1: 3W (9pts), t2: 2W (6pts), t3: 1W (3pts), t4: 0W (0pts)
    matches = [
      Match.create!(home_team: t1, away_team: t2, home_score: 2, away_score: 0, status: "PostEvent", stage: "Group Stage", match_id: "standings-1", start_time: 1.day.ago),
      Match.create!(home_team: t1, away_team: t3, home_score: 1, away_score: 0, status: "PostEvent", stage: "Group Stage", match_id: "standings-2", start_time: 1.day.ago),
      Match.create!(home_team: t1, away_team: t4, home_score: 3, away_score: 0, status: "PostEvent", stage: "Group Stage", match_id: "standings-3", start_time: 1.day.ago),
      Match.create!(home_team: t2, away_team: t3, home_score: 2, away_score: 1, status: "PostEvent", stage: "Group Stage", match_id: "standings-4", start_time: 1.day.ago),
      Match.create!(home_team: t2, away_team: t4, home_score: 1, away_score: 0, status: "PostEvent", stage: "Group Stage", match_id: "standings-5", start_time: 1.day.ago),
      Match.create!(home_team: t3, away_team: t4, home_score: 1, away_score: 0, status: "PostEvent", stage: "Group Stage", match_id: "standings-6", start_time: 1.day.ago)
    ]

    result = TournamentSimulation.calculate_standings([t1, t2, t3, t4], matches)

    assert_equal [t1.id, t2.id, t3.id, t4.id], result.map(&:id)
  end

  test "calculate_standings breaks ties by goal difference" do
    t1 = Team.create!(name: "TieA_#{SecureRandom.hex(4)}")
    t2 = Team.create!(name: "TieB_#{SecureRandom.hex(4)}")
    t3 = Team.create!(name: "TieC_#{SecureRandom.hex(4)}")
    t4 = Team.create!(name: "TieD_#{SecureRandom.hex(4)}")

    # t1: beats t3 3-0 (3pts, GD+3), t2: beats t4 1-0 (3pts, GD+1) — t1 wins on GD
    matches = [
      Match.create!(home_team: t1, away_team: t3, home_score: 3, away_score: 0, status: "PostEvent", stage: "Group Stage", match_id: "gd-1", start_time: 1.day.ago),
      Match.create!(home_team: t2, away_team: t4, home_score: 1, away_score: 0, status: "PostEvent", stage: "Group Stage", match_id: "gd-2", start_time: 1.day.ago),
      Match.create!(home_team: t1, away_team: t2, home_score: 0, away_score: 0, status: "PostEvent", stage: "Group Stage", match_id: "gd-3", start_time: 1.day.ago),
      Match.create!(home_team: t3, away_team: t4, home_score: 0, away_score: 0, status: "PostEvent", stage: "Group Stage", match_id: "gd-4", start_time: 1.day.ago)
    ]

    result = TournamentSimulation.calculate_standings([t1, t2, t3, t4], matches)
    assert_equal t1.id, result[0].id, "t1 should lead on goal difference"
    assert_equal t2.id, result[1].id, "t2 should be second"
  end

  test "calculate_standings breaks ties by goals scored when points and gd are equal" do
    t1 = Team.create!(name: "GFA_#{SecureRandom.hex(4)}")
    t2 = Team.create!(name: "GFB_#{SecureRandom.hex(4)}")
    t3 = Team.create!(name: "GFC_#{SecureRandom.hex(4)}")
    t4 = Team.create!(name: "GFD_#{SecureRandom.hex(4)}")

    # t1: wins 3-1 (3pts, GD+2, GF=3), t2: wins 2-0 (3pts, GD+2, GF=2) — t1 wins on goals scored
    matches = [
      Match.create!(home_team: t1, away_team: t3, home_score: 3, away_score: 1, status: "PostEvent", stage: "Group Stage", match_id: "gf-1", start_time: 1.day.ago),
      Match.create!(home_team: t2, away_team: t4, home_score: 2, away_score: 0, status: "PostEvent", stage: "Group Stage", match_id: "gf-2", start_time: 1.day.ago),
      Match.create!(home_team: t1, away_team: t2, home_score: 0, away_score: 0, status: "PostEvent", stage: "Group Stage", match_id: "gf-3", start_time: 1.day.ago),
      Match.create!(home_team: t3, away_team: t4, home_score: 0, away_score: 0, status: "PostEvent", stage: "Group Stage", match_id: "gf-4", start_time: 1.day.ago)
    ]

    result = TournamentSimulation.calculate_standings([t1, t2, t3, t4], matches)
    assert_equal t1.id, result[0].id, "t1 should lead on goals scored"
    assert_equal t2.id, result[1].id, "t2 should be second"
  end

  # ── standing_stats ───────────────────────────────────────────────────────

  test "standing_stats returns correct pts and gd for a team" do
    t1 = Team.create!(name: "StatsA_#{SecureRandom.hex(4)}")
    t2 = Team.create!(name: "StatsB_#{SecureRandom.hex(4)}")
    t3 = Team.create!(name: "StatsC_#{SecureRandom.hex(4)}")

    matches = [
      Match.create!(home_team: t1, away_team: t2, home_score: 2, away_score: 1, status: "PostEvent", stage: "Group Stage", match_id: "stats-1", start_time: 1.day.ago),
      Match.create!(home_team: t1, away_team: t3, home_score: 1, away_score: 1, status: "PostEvent", stage: "Group Stage", match_id: "stats-2", start_time: 1.day.ago)
    ]

    stats = TournamentSimulation.standing_stats(t1, matches)

    assert_equal 4, stats[:pts]  # 3 (win) + 1 (draw)
    assert_equal 1, stats[:gd]   # (2-1) + (1-1)
    assert_equal 3, stats[:gf]   # 2 + 1
  end
end
