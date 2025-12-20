require "test_helper"

class MatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @home_team = Team.create!(name: "Argentina", flag_url: "https://flagcdn.com/ar.svg")
    @away_team = Team.create!(name: "France", flag_url: "https://flagcdn.com/fr.svg")
  end

  test "should get index" do
    get matches_url
    assert_response :success
  end

  test "assign_points awards 0 points for group stage matches" do
    match = Match.create!(
      home_team: @home_team,
      away_team: @away_team,
      stage: "Group Stage",
      status: "PostEvent",
      winner: "home",
      match_id: "test-1",
      start_time: Time.now
    )

    @controller = MatchesController.new
    @controller.send(:assign_points, match)

    assert_equal 0, match.home_points
    assert_equal 0, match.away_points
  end

  test "assign_points awards progression point when team first plays knockout match" do
    # Team starts with 0 points and not progressed
    assert_equal 0, @home_team.points
    assert_not @home_team.progressed?

    match = Match.create!(
      home_team: @home_team,
      away_team: @away_team,
      stage: "Last 16",
      status: "PostEvent",
      winner: "home",
      match_id: "test-2",
      start_time: Time.now
    )

    @controller = MatchesController.new
    @controller.send(:assign_points, match)

    # Team should be marked as progressed and get 1 point for progression
    @home_team.reload
    assert @home_team.progressed?
    # Should have 1 (progression) + 1 (winning last 16) = 2 points
    assert_equal 2, @home_team.points
  end

  test "assign_points awards 1 point for winning Last 16" do
    match = Match.create!(
      home_team: @home_team,
      away_team: @away_team,
      stage: "Last 16",
      status: "PostEvent",
      winner: "home",
      match_id: "test-3",
      start_time: Time.now
    )

    @controller = MatchesController.new
    @controller.send(:assign_points, match)

    assert_equal 1, match.home_points
    assert_equal 0, match.away_points
  end

  test "assign_points awards 1 point for winning Quarter-finals" do
    @home_team.update!(progressed: true, points: 2) # Already progressed

    match = Match.create!(
      home_team: @home_team,
      away_team: @away_team,
      stage: "Quarter-finals",
      status: "PostEvent",
      winner: "home",
      match_id: "test-4",
      start_time: Time.now
    )

    @controller = MatchesController.new
    @controller.send(:assign_points, match)

    assert_equal 1, match.home_points
    assert_equal 0, match.away_points
  end

  test "assign_points awards 2 points to final winner and 1 to loser" do
    @home_team.update!(progressed: true, points: 4) # Already progressed
    @away_team.update!(progressed: true, points: 4)

    match = Match.create!(
      home_team: @home_team,
      away_team: @away_team,
      stage: "Final",
      status: "PostEvent",
      winner: "home",
      match_id: "test-5",
      start_time: Time.now
    )

    @controller = MatchesController.new
    @controller.send(:assign_points, match)

    assert_equal 2, match.home_points
    assert_equal 1, match.away_points

    @home_team.reload
    @away_team.reload

    # Home team: 4 (existing) + 2 (final win) = 6
    assert_equal 6, @home_team.points
    # Away team: 4 (existing) + 1 (final loss) = 5
    assert_equal 5, @away_team.points
  end

  test "assign_points only awards progression point once per team" do
    # First knockout match
    match1 = Match.create!(
      home_team: @home_team,
      away_team: @away_team,
      stage: "Last 16",
      status: "PostEvent",
      winner: "home",
      match_id: "test-6",
      start_time: Time.now
    )

    @controller = MatchesController.new
    @controller.send(:assign_points, match1)

    @home_team.reload
    points_after_first_match = @home_team.points
    # Should have 1 (progression) + 1 (winning) = 2

    # Second knockout match for same team
    @away_team2 = Team.create!(name: "Croatia", flag_url: "https://flagcdn.com/hr.svg")
    match2 = Match.create!(
      home_team: @home_team,
      away_team: @away_team2,
      stage: "Quarter-finals",
      status: "PostEvent",
      winner: "home",
      match_id: "test-7",
      start_time: Time.now + 1.day
    )

    @controller.send(:assign_points, match2)

    @home_team.reload
    # Should only add 1 for winning QF, not another progression point
    # Total: 2 (from before) + 1 (QF win) = 3
    assert_equal points_after_first_match + 1, @home_team.points
  end
end
