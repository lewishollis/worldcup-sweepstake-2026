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

  # ── assign_simulation_points ─────────────────────────────────────────────

  test "assign_simulation_points awards 0 points for Group Stage" do
    friend = Friend.create!(name: "GS_#{SecureRandom.hex(4)}")
    group  = Group.create!(name: "GS_Group_#{SecureRandom.hex(4)}", multiplier: 3, friend: friend)
    home   = Team.create!(name: "GS_Home_#{SecureRandom.hex(4)}")
    away   = Team.create!(name: "GS_Away_#{SecureRandom.hex(4)}")
    group.teams << [home, away]

    match = Match.new(
      home_team: home, away_team: away,
      home_score: 2, away_score: 1, winner: "home",
      status: "PostEvent", stage: "Group Stage",
      start_time: Time.now, match_id: "gs-pts-#{SecureRandom.hex(4)}"
    )

    TournamentSimulation.assign_simulation_points(match)

    assert_equal 0, match.home_points
    assert_equal 0, match.away_points
    assert_equal 0, home.reload.points
    assert_equal 0, away.reload.points
  end

  test "assign_simulation_points awards progression + win point in Last 16" do
    friend = Friend.create!(name: "L16_#{SecureRandom.hex(4)}")
    group  = Group.create!(name: "L16_Group_#{SecureRandom.hex(4)}", multiplier: 3, friend: friend)
    home   = Team.create!(name: "L16_Home_#{SecureRandom.hex(4)}")
    away   = Team.create!(name: "L16_Away_#{SecureRandom.hex(4)}")
    group.teams << [home, away]

    match = Match.new(
      home_team: home, away_team: away,
      home_score: 2, away_score: 1, winner: "home",
      status: "PostEvent", stage: "Last 16",
      start_time: Time.now, match_id: "l16-pts-#{SecureRandom.hex(4)}"
    )

    TournamentSimulation.assign_simulation_points(match)

    assert_equal 1, match.home_points
    assert_equal 0, match.away_points
    assert_equal 2, home.reload.points  # +1 progression, +1 win
    assert_equal 1, away.reload.points  # +1 progression, +0 win
    assert home.reload.progressed?
    assert away.reload.progressed?
  end

  test "assign_simulation_points does not double-award progression points" do
    friend = Friend.create!(name: "Prog_#{SecureRandom.hex(4)}")
    group  = Group.create!(name: "Prog_Group_#{SecureRandom.hex(4)}", multiplier: 3, friend: friend)
    home   = Team.create!(name: "Prog_Home_#{SecureRandom.hex(4)}", progressed: true, points: 1)
    away   = Team.create!(name: "Prog_Away_#{SecureRandom.hex(4)}", progressed: true, points: 1)
    group.teams << [home, away]

    match = Match.new(
      home_team: home, away_team: away,
      home_score: 1, away_score: 0, winner: "home",
      status: "PostEvent", stage: "Quarter-finals",
      start_time: Time.now, match_id: "prog-pts-#{SecureRandom.hex(4)}"
    )

    TournamentSimulation.assign_simulation_points(match)

    # Already progressed → no extra progression point, just win point for home
    assert_equal 2, home.reload.points  # was 1, +1 win
    assert_equal 1, away.reload.points  # was 1, +0
  end

  test "assign_simulation_points awards 2 to Final winner and 1 to runner-up" do
    friend = Friend.create!(name: "Final_#{SecureRandom.hex(4)}")
    group  = Group.create!(name: "Final_Group_#{SecureRandom.hex(4)}", multiplier: 3, friend: friend)
    home   = Team.create!(name: "Final_Home_#{SecureRandom.hex(4)}", progressed: true, points: 3)
    away   = Team.create!(name: "Final_Away_#{SecureRandom.hex(4)}", progressed: true, points: 3)
    group.teams << [home, away]

    match = Match.new(
      home_team: home, away_team: away,
      home_score: 1, away_score: 0, winner: "home",
      status: "PostEvent", stage: "Final",
      start_time: Time.now, match_id: "final-pts-#{SecureRandom.hex(4)}"
    )

    TournamentSimulation.assign_simulation_points(match)

    assert_equal 2, match.home_points
    assert_equal 1, match.away_points
    assert_equal 5, home.reload.points  # was 3, +2
    assert_equal 4, away.reload.points  # was 3, +1
  end

  # ── full integration ─────────────────────────────────────────────────────

  def build_simulation_data
    12.times do |g|
      friend = Friend.create!(name: "SimFriend#{g}_#{SecureRandom.hex(4)}")
      group  = Group.create!(name: "SimGroup#{g}", multiplier: 3, friend: friend)
      4.times do |t|
        team = Team.create!(name: "SimTeam#{g}_#{t}_#{SecureRandom.hex(4)}")
        group.teams << team
      end
    end
  end

  test "simulate task aborts when user types 'no'" do
    build_simulation_data

    STDIN.stub(:gets, "no\n") do
      assert_output(/Cancelled/) do
        Rake::Task["tournament:simulate"].invoke
      end
    end

    assert_equal 0, Match.count
  end

  # ── simulate_knockout_match ──────────────────────────────────────────────

  test "simulate_knockout_match creates a PostEvent match with a winner and awards points" do
    friend = Friend.create!(name: "KO_#{SecureRandom.hex(4)}")
    group  = Group.create!(name: "KO_Group_#{SecureRandom.hex(4)}", multiplier: 3, friend: friend)
    home   = Team.create!(name: "KO_Home_#{SecureRandom.hex(4)}")
    away   = Team.create!(name: "KO_Away_#{SecureRandom.hex(4)}")
    group.teams << [home, away]

    match = TournamentSimulation.simulate_knockout_match(home, away, "Quarter-finals", 1, "test-qf")

    assert match.persisted?
    assert_equal "PostEvent", match.status
    assert_equal "Quarter-finals", match.stage
    assert_includes %w[home away], match.winner
    assert match.home_score != match.away_score, "knockout match must have a winner (no draw)"
    total_pts = home.reload.points + away.reload.points
    assert total_pts >= 2, "both teams should have at least 1 progression point each"
  end
end
