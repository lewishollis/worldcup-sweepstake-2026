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

  test "progression_score ignores PreEvent and MidEvent knockout matches" do
    Match.create!(home_team: @team, away_team: @opponent, stage: "Last 32",
                  status: "PreEvent", winner: nil, match_id: "r32-pre",
                  start_time: 1.day.from_now)
    assert_equal 0.0, @team.reload.progression_score
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
end
