require "test_helper"

class UpcomingMatchesInsightServiceTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  def setup
    travel_to Time.zone.local(2026, 6, 10, 9, 0, 0)

    @richard = Friend.create!(name: "Richard")
    @jamie   = Friend.create!(name: "Jamie")
    @mexico  = Team.create!(name: "Mexico", flag_url: "https://x.com/mx.svg")
    @safrica = Team.create!(name: "South Africa", flag_url: "https://x.com/za.svg")
    @spain   = Team.create!(name: "Spain", flag_url: "https://x.com/es.svg")
    @haiti   = Team.create!(name: "Haiti", flag_url: "https://x.com/ht.svg")
    Group.create!(name: "Group 8", friend: @richard).teams << @mexico
    Group.create!(name: "Group 2", friend: @jamie).teams << @safrica

    @tomorrow_match = Match.create!(
      home_team: @mexico, away_team: @safrica, stage: "Group Stage", status: "PreEvent",
      match_id: "umis-1", home_score: 0, away_score: 0,
      start_time: Time.zone.local(2026, 6, 11, 20, 0, 0),
      home_friend_name: "No owner", away_friend_name: "No owner"
    )
    @later_match = Match.create!(
      home_team: @spain, away_team: @haiti, stage: "Group Stage", status: "PreEvent",
      match_id: "umis-2", home_score: 0, away_score: 0,
      start_time: Time.zone.local(2026, 6, 13, 17, 0, 0)
    )
  end

  def teardown
    travel_back
  end

  test "scopes prompt to the next match day only" do
    service = UpcomingMatchesInsightService.new([@later_match, @tomorrow_match])
    prompt = service.send(:build_user_message)

    assert_includes prompt, "MATCHES ON THURSDAY 11 JUNE 2026"
    assert_includes prompt, "Mexico"
    refute_includes prompt, "Spain", "matches on later days must not appear in the prompt"
  end

  test "every match line carries its full date and UK kick-off time" do
    service = UpcomingMatchesInsightService.new([@tomorrow_match])
    prompt = service.send(:build_user_message)

    assert_includes prompt, "Thursday 11 June 2026, 20:00 UK time"
  end

  test "ownership comes from live group assignments, not stale match columns" do
    service = UpcomingMatchesInsightService.new([@tomorrow_match])
    prompt = service.send(:build_user_message)

    assert_includes prompt, "Mexico (Richard)"
    assert_includes prompt, "South Africa (Jamie)"
  end

  test "system prompt casts John Botson in Danny Dyer's voice without relaxing accuracy" do
    service = UpcomingMatchesInsightService.new([@tomorrow_match])
    prompt = service.send(:build_system_prompt, TournamentContextService.new)

    assert_includes prompt, "John Botson"
    assert_includes prompt, "Danny Dyer"
    # The voice changes the wording, never the facts — accuracy rules must survive
    assert_includes prompt, "never invent scores, points, or positions"
    assert_includes prompt, "ONLY discuss the matches listed"
    assert_includes prompt, "Never state or imply a different date"
  end

  test "cache version is tied to the persona so a persona change regenerates the insight" do
    service = UpcomingMatchesInsightService.new([@tomorrow_match])
    version = service.send(:cache_version)

    original = UpcomingMatchesInsightService::PERSONA_VERSION
    UpcomingMatchesInsightService.send(:remove_const, :PERSONA_VERSION)
    UpcomingMatchesInsightService.const_set(:PERSONA_VERSION, "someone-else-v9")
    begin
      refute_equal version, service.send(:cache_version)
    ensure
      UpcomingMatchesInsightService.send(:remove_const, :PERSONA_VERSION)
      UpcomingMatchesInsightService.const_set(:PERSONA_VERSION, original)
    end
  end

  test "returns nil when there are no upcoming matches" do
    assert_nil UpcomingMatchesInsightService.call([])
  end

  test "past-only match lists produce no insight" do
    travel_to Time.zone.local(2026, 7, 20, 9, 0, 0)
    assert_nil UpcomingMatchesInsightService.call([@tomorrow_match, @later_match])
  end

  test "cache version changes when the date changes" do
    service = UpcomingMatchesInsightService.new([@tomorrow_match])
    version_today = service.send(:cache_version)

    travel_to Time.zone.local(2026, 6, 11, 9, 0, 0)
    version_tomorrow = service.send(:cache_version)

    refute_equal version_today, version_tomorrow, "a new day must invalidate the cached insight"
  end

  test "generated insight is cached but the fallback is not" do
    GroqClient.stub(:call, nil) do
      result = UpcomingMatchesInsightService.call([@tomorrow_match])
      assert_equal "Check the standings for today's sweepstake picture.", result
      assert_equal 0, AiInsightCache.where(key: "upcoming_matches_insight").count
    end

    GroqClient.stub(:call, "Real insight about Mexico vs South Africa.") do
      result = UpcomingMatchesInsightService.call([@tomorrow_match])
      assert_equal "Real insight about Mexico vs South Africa.", result
      assert_equal 1, AiInsightCache.where(key: "upcoming_matches_insight").count
    end
  end
end
