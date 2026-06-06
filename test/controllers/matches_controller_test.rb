require "test_helper"

class MatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @home_team = Team.create!(name: "Argentina", flag_url: "https://flagcdn.com/ar.svg")
    @away_team = Team.create!(name: "France", flag_url: "https://flagcdn.com/fr.svg")
  end

  test "visiting matches page redirects to PreEvent filter" do
    get matches_url
    assert_response :redirect
  end

  test "saving a match persists stage and winner from API data" do
    match = Match.find_or_initialize_by(match_id: "persist-test-1")
    match.assign_attributes(
      home_team: @home_team,
      away_team: @away_team,
      start_time: 1.day.ago,
      stage: "Last 32",
      status: "PostEvent",
      winner: "home",
      home_score: 2,
      away_score: 1,
      accessible_event_summary: "Argentina beat France"
    )
    match.save!

    assert_equal "Last 32", match.reload.stage
    assert_equal "home", match.reload.winner
  end

  test "team progression_score updates automatically when a new match is saved" do
    assert_equal 0.0, @home_team.progression_score

    Match.create!(
      home_team: @home_team,
      away_team: @away_team,
      stage: "Last 32",
      status: "PostEvent",
      winner: "home",
      match_id: "auto-score-test",
      start_time: 1.day.ago
    )

    # 1.0 for qualifying + 1.0 for winning Last 32 = 2.0
    assert_equal 2.0, @home_team.reload.progression_score
  end
end
