require "test_helper"

class TeamTest < ActiveSupport::TestCase
  setup do
    @team = Team.create!(name: "Brazil", flag_url: "https://example.com/br.svg")
    @opponent = Team.create!(name: "France", flag_url: "https://example.com/fr.svg")
  end

  # --- progression_score ---

  test "progression_score is 0.0 for a team with no matches" do
    assert_equal 0.0, @team.progression_score
  end

  test "progression_score is 0.0 for a team with only group stage matches" do
    Match.create!(home_team: @team, away_team: @opponent, stage: "Group Stage",
                  status: "PostEvent", winner: "home", match_id: "gs-1",
                  start_time: 1.day.ago)
    assert_equal 0.0, @team.reload.progression_score
  end

  test "progression_score is 1.0 for a team knocked out in Last 32" do
    Match.create!(home_team: @team, away_team: @opponent, stage: "Last 32",
                  status: "PostEvent", winner: "away", match_id: "r32-1",
                  start_time: 1.day.ago)
    assert_equal 1.0, @team.reload.progression_score
  end

  test "progression_score is 2.0 for a team that wins Last 32 then loses Last 16" do
    Match.create!(home_team: @team, away_team: @opponent, stage: "Last 32",
                  status: "PostEvent", winner: "home", match_id: "r32-1",
                  start_time: 2.days.ago)
    Match.create!(home_team: @team, away_team: @opponent, stage: "Last 16",
                  status: "PostEvent", winner: "away", match_id: "r16-1",
                  start_time: 1.day.ago)
    assert_equal 2.0, @team.reload.progression_score
  end

  test "progression_score is 3.0 for a team that wins Last 32 and Last 16 then loses QF" do
    Match.create!(home_team: @team, away_team: @opponent, stage: "Last 32",
                  status: "PostEvent", winner: "home", match_id: "r32-1",
                  start_time: 3.days.ago)
    Match.create!(home_team: @team, away_team: @opponent, stage: "Last 16",
                  status: "PostEvent", winner: "home", match_id: "r16-1",
                  start_time: 2.days.ago)
    Match.create!(home_team: @team, away_team: @opponent, stage: "Quarter-finals",
                  status: "PostEvent", winner: "away", match_id: "qf-1",
                  start_time: 1.day.ago)
    assert_equal 3.0, @team.reload.progression_score
  end

  test "progression_score is 4.0 for a team that wins through to SF then loses" do
    Match.create!(home_team: @team, away_team: @opponent, stage: "Last 32",
                  status: "PostEvent", winner: "home", match_id: "r32-1",
                  start_time: 4.days.ago)
    Match.create!(home_team: @team, away_team: @opponent, stage: "Last 16",
                  status: "PostEvent", winner: "home", match_id: "r16-1",
                  start_time: 3.days.ago)
    Match.create!(home_team: @team, away_team: @opponent, stage: "Quarter-finals",
                  status: "PostEvent", winner: "home", match_id: "qf-1",
                  start_time: 2.days.ago)
    Match.create!(home_team: @team, away_team: @opponent, stage: "Semi-finals",
                  status: "PostEvent", winner: "away", match_id: "sf-1",
                  start_time: 1.day.ago)
    assert_equal 4.0, @team.reload.progression_score
  end

  test "progression_score is 4.5 for the 3rd place winner" do
    Match.create!(home_team: @team, away_team: @opponent, stage: "Last 32",
                  status: "PostEvent", winner: "home", match_id: "r32-1",
                  start_time: 5.days.ago)
    Match.create!(home_team: @team, away_team: @opponent, stage: "Last 16",
                  status: "PostEvent", winner: "home", match_id: "r16-1",
                  start_time: 4.days.ago)
    Match.create!(home_team: @team, away_team: @opponent, stage: "Quarter-finals",
                  status: "PostEvent", winner: "home", match_id: "qf-1",
                  start_time: 3.days.ago)
    Match.create!(home_team: @team, away_team: @opponent, stage: "Semi-finals",
                  status: "PostEvent", winner: "away", match_id: "sf-1",
                  start_time: 2.days.ago)
    Match.create!(home_team: @team, away_team: @opponent, stage: "3rd Place Final",
                  status: "PostEvent", winner: "home", match_id: "3rd-1",
                  start_time: 1.day.ago)
    assert_equal 4.5, @team.reload.progression_score
  end

  test "progression_score is 6.0 for the champion" do
    Match.create!(home_team: @team, away_team: @opponent, stage: "Last 32",
                  status: "PostEvent", winner: "home", match_id: "r32-1",
                  start_time: 5.days.ago)
    Match.create!(home_team: @team, away_team: @opponent, stage: "Last 16",
                  status: "PostEvent", winner: "home", match_id: "r16-1",
                  start_time: 4.days.ago)
    Match.create!(home_team: @team, away_team: @opponent, stage: "Quarter-finals",
                  status: "PostEvent", winner: "home", match_id: "qf-1",
                  start_time: 3.days.ago)
    Match.create!(home_team: @team, away_team: @opponent, stage: "Semi-finals",
                  status: "PostEvent", winner: "home", match_id: "sf-1",
                  start_time: 2.days.ago)
    Match.create!(home_team: @team, away_team: @opponent, stage: "Final",
                  status: "PostEvent", winner: "home", match_id: "f-1",
                  start_time: 1.day.ago)
    assert_equal 6.0, @team.reload.progression_score
  end

  test "progression_score is 5.0 for the runner-up" do
    Match.create!(home_team: @team, away_team: @opponent, stage: "Last 32",
                  status: "PostEvent", winner: "home", match_id: "r32-1",
                  start_time: 5.days.ago)
    Match.create!(home_team: @team, away_team: @opponent, stage: "Last 16",
                  status: "PostEvent", winner: "home", match_id: "r16-1",
                  start_time: 4.days.ago)
    Match.create!(home_team: @team, away_team: @opponent, stage: "Quarter-finals",
                  status: "PostEvent", winner: "home", match_id: "qf-1",
                  start_time: 3.days.ago)
    Match.create!(home_team: @team, away_team: @opponent, stage: "Semi-finals",
                  status: "PostEvent", winner: "home", match_id: "sf-1",
                  start_time: 2.days.ago)
    Match.create!(home_team: @team, away_team: @opponent, stage: "Final",
                  status: "PostEvent", winner: "away", match_id: "f-1",
                  start_time: 1.day.ago)
    assert_equal 5.0, @team.reload.progression_score
  end

  test "progression_score counts win correctly when team is away" do
    Match.create!(home_team: @opponent, away_team: @team, stage: "Last 32",
                  status: "PostEvent", winner: "away", match_id: "r32-away",
                  start_time: 1.day.ago)
    assert_equal 2.0, @team.reload.progression_score
  end

  test "progression_score is 0.5 when team only plays and wins 3rd Place Final (no main bracket)" do
    Match.create!(home_team: @team, away_team: @opponent, stage: "3rd Place Final",
                  status: "PostEvent", winner: "home", match_id: "3rd-only",
                  start_time: 1.day.ago)
    assert_equal 0.5, @team.reload.progression_score
  end

  test "progression_score awards the qualification bonus for a knockout fixture before kick-off" do
    Match.create!(home_team: @team, away_team: @opponent, stage: "Last 32",
                  status: "PreEvent", winner: nil, match_id: "r32-pre",
                  start_time: 1.day.from_now)
    # +1 for reaching the main bracket; no win points until the game is played.
    assert_equal 1.0, @team.reload.progression_score
  end

  test "progression_score does not award win points for an unfinished knockout game" do
    Match.create!(home_team: @team, away_team: @opponent, stage: "Last 32",
                  status: "PostEvent", winner: "home", match_id: "r32-played",
                  start_time: 2.days.ago)
    Match.create!(home_team: @team, away_team: @opponent, stage: "Last 16",
                  status: "PreEvent", winner: nil, match_id: "r16-pre",
                  start_time: 1.day.from_now)
    # +1 qualification, +1 for the won Last 32 — but nothing for the pending Last 16.
    assert_equal 2.0, @team.reload.progression_score
  end

  # --- progressed? ---

  test "progressed? is false for a team with no knockout matches played" do
    assert_not @team.progressed?
  end

  test "progressed? is false for a team with only group stage matches" do
    Match.create!(home_team: @team, away_team: @opponent, stage: "Group Stage",
                  status: "PostEvent", winner: "home", match_id: "gs-1",
                  start_time: 1.day.ago)
    assert_not @team.reload.progressed?
  end

  test "progressed? is true once a knockout match is PostEvent" do
    Match.create!(home_team: @team, away_team: @opponent, stage: "Last 32",
                  status: "PostEvent", winner: "away", match_id: "r32-1",
                  start_time: 1.day.ago)
    assert @team.reload.progressed?
  end

  test "progressed? is true once a knockout fixture exists, even before kick-off" do
    Match.create!(home_team: @team, away_team: @opponent, stage: "Last 32",
                  status: "PreEvent", winner: nil, match_id: "r32-pre",
                  start_time: 1.day.from_now)
    assert @team.reload.progressed?
  end

  test "progressed? and the +1 are awarded on a clinched top-2 finish before any knockout fixture exists" do
    clinch_team_in_group!(@team)
    # No knockout fixture for the team yet — only the clinched group finish.
    assert @team.reload.progressed?
    assert_equal 1.0, @team.reload.progression_score
  end

  # Builds a group where `team` has mathematically clinched a top-2 finish:
  # it wins all three group games, so it is top 2 in every remaining completion.
  def clinch_team_in_group!(team)
    KnockoutQualification.reset!
    b = Team.create!(name: "Grp-B", flag_url: "https://x/b.svg")
    c = Team.create!(name: "Grp-C", flag_url: "https://x/c.svg")
    d = Team.create!(name: "Grp-D", flag_url: "https://x/d.svg")
    [b, c, d].each_with_index do |opp, i|
      Match.create!(home_team: team, away_team: opp, stage: "Group Stage", status: "PostEvent",
                    group_name: "Group Z", home_score: 1, away_score: 0,
                    match_id: "gz-#{i}", start_time: (3 - i).days.ago)
    end
  end

  # --- canonical_name ---

  test "canonical_name maps BBC API names to seed names" do
    assert_equal "Korea Republic", Team.canonical_name("South Korea")
    assert_equal "Czechia", Team.canonical_name("Czech Republic")
    assert_equal "Bosnia And Herz.", Team.canonical_name("Bosnia-Herzegovina")
    assert_equal "USA", Team.canonical_name("United States")
    assert_equal "Türkiye", Team.canonical_name("Turkey")
    assert_equal "IR Iran", Team.canonical_name("Iran")
    assert_equal "Cabo Verde", Team.canonical_name("Cape Verde")
    assert_equal "Côte d'Ivoire", Team.canonical_name("Ivory Coast")
  end

  test "canonical_name passes through names that already match seeds" do
    assert_equal "Brazil", Team.canonical_name("Brazil")
    assert_nil Team.canonical_name(nil)
  end
end
