require "test_helper"

class AiLeaderboardInsightsServiceTest < ActiveSupport::TestCase
  def team(name)
    Team.create!(name: name, flag_url: "https://x.com/#{name}.svg")
  end

  test "analysis computes position and points from real Group scoring" do
    leader = Friend.create!(name: "Leader")
    chaser = Friend.create!(name: "Chaser")
    lg = Group.create!(name: "LG", friend: leader)
    cg = Group.create!(name: "CG", friend: chaser)
    spain = team("Spain"); france = team("France")
    lg.teams << spain
    cg.teams << france
    # Leader's team wins a Last 32 tie (qualify +1, win +1 = 2.0); chaser's team
    # appears in Last 32 but loses (qualify +1 = 1.0).
    Match.create!(home_team: spain, away_team: france, stage: "Last 32", status: "PostEvent",
                  match_id: "al-ko", home_score: 1, away_score: 0, winner: "home",
                  start_time: Time.zone.local(2026, 7, 1, 17, 0, 0))

    analysis = AiLeaderboardInsightsService.new(chaser).send(:build_analysis)
    assert_equal 2, analysis[:position]
    assert_operator analysis[:leader_points], :>, analysis[:points]
  end

  test "user message includes the friend's teams' group situations" do
    friend = Friend.create!(name: "Ben")
    group  = Group.create!(name: "BG", friend: friend)
    qatar  = team("Qatar"); brazil = team("Brazil")
    group.teams << qatar
    Match.create!(home_team: qatar, away_team: brazil, stage: "Group Stage", status: "PostEvent",
                  group_name: "Group B", match_id: "al-grp", home_score: 1, away_score: 0,
                  start_time: Time.zone.local(2026, 6, 13, 17, 0, 0))

    service  = AiLeaderboardInsightsService.new(friend)
    analysis = service.send(:build_analysis)
    msg      = service.send(:build_user_message, analysis)

    assert_includes msg, "Qatar"
    assert_includes msg, "Group B"
  end

  test "prompt carries world rankings and permits strength judgement strictly from them" do
    friend = Friend.create!(name: "Lewis")
    group  = Group.create!(name: "LG", friend: friend)
    portugal = team("Portugal"); rival = team("Panama")
    portugal.update_column(:fifa_rank, 5)
    rival.update_column(:fifa_rank, 34)
    group.teams << portugal
    Match.create!(home_team: portugal, away_team: rival, stage: "Group Stage", status: "PostEvent",
                  group_name: "Group F", match_id: "al-str", home_score: 1, away_score: 0,
                  start_time: Time.zone.local(2026, 6, 13, 17, 0, 0))

    service  = AiLeaderboardInsightsService.new(friend)
    user_msg = service.send(:build_user_message, service.send(:build_analysis))
    sys_msg  = service.send(:build_system_prompt)

    assert_includes user_msg, "Portugal (world #5)"
    assert_includes user_msg, "world #34" # rival's rank, for judging group difficulty
    assert_includes sys_msg, "STRENGTH"
    assert_includes sys_msg, "never on outside knowledge"
  end

  test "FIFA_RANKS snapshot covers the 48-team field with sane values" do
    assert_equal 48, Team::FIFA_RANKS.size
    assert_equal 5, Team::FIFA_RANKS["Portugal"]
    assert_equal 1, Team::FIFA_RANKS["Argentina"]
  end

  test "returns a winner message for the friend in first place" do
    friend = Friend.create!(name: "Solo")
    Group.create!(name: "SG", friend: friend).teams << team("Portugal")
    result = AiLeaderboardInsightsService.new(friend).generate_personalized_insight
    assert_equal 1, result[:analysis][:position]
    assert_includes result[:commentary], "leading"
  end
end
