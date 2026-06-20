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

  test "index renders without error when group data exists" do
    get matches_path(filter: { PostEvent: "1" })
    assert_response :success
  end

  test "qualification badge renders Through for a clinched team and nothing for an ungrouped team" do
    a = Team.create!(name: "Aa", flag_url: "https://x.com/Aa.svg")
    b = Team.create!(name: "Bb", flag_url: "https://x.com/Bb.svg")
    c = Team.create!(name: "Cc", flag_url: "https://x.com/Cc.svg")
    d = Team.create!(name: "Dd", flag_url: "https://x.com/Dd.svg")
    [[a, b], [a, c], [a, d], [b, c], [b, d], [c, d]].each_with_index do |(h, w), i|
      Match.create!(home_team: h, away_team: w, stage: "Group Stage", status: "PostEvent",
                    group_name: "G1", match_id: "qb-#{i}", home_score: 1, away_score: 0,
                    start_time: Time.zone.local(2026, 6, 13, 17, 0, 0))
    end

    through = ApplicationController.render(partial: "shared/qualification_badge", locals: { team: a })
    assert_includes through, "Through"

    zz = Team.create!(name: "Zz", flag_url: "https://x.com/Zz.svg")
    ungrouped = ApplicationController.render(partial: "shared/qualification_badge", locals: { team: zz })
    assert_equal "", ungrouped.strip
  end

  test "per-match preview box is temporarily disabled (focus is the daily summary)" do
    home = Team.create!(name: "Qatar", flag_url: "https://x.com/qa.svg")
    away = Team.create!(name: "Switzerland", flag_url: "https://x.com/ch.svg")
    upcoming = Match.create!(home_team: home, away_team: away, stage: "Group Stage", status: "PreEvent",
                             group_name: "Group B", match_id: "mc-upcoming",
                             start_time: Time.zone.local(2026, 6, 17, 17, 0, 0))

    get match_path(upcoming)

    assert_response :success
    assert_select "h3.commentary-title", false # the John Botson preview box is not rendered
  end
end
