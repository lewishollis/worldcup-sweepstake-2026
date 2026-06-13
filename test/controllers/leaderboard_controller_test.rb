require "test_helper"

class LeaderboardControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get leaderboard_index_url
    assert_response :success
  end

  test "per-friend insight is temporarily disabled (focus is the daily summary)" do
    friend = Friend.create!(name: "Ben")
    group  = Group.create!(name: "Group 3", friend: friend)
    group.teams << Team.create!(name: "Qatar", flag_url: "https://x.com/qa.svg")

    get leaderboard_path(group)

    assert_response :success
    assert_select "h3.insights-title", false # the per-friend insight box is not rendered
  end
end
