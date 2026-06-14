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
      group_name: "Group A",
      home_friend_name: "No owner", away_friend_name: "No owner"
    )
    @later_match = Match.create!(
      home_team: @spain, away_team: @haiti, stage: "Group Stage", status: "PreEvent",
      match_id: "umis-2", home_score: 0, away_score: 0,
      start_time: Time.zone.local(2026, 6, 13, 17, 0, 0),
      group_name: "Group H"
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

  test "the briefing ends with a verified football fact, not a generic sign-off" do
    GroqClient.stub(:call, "Two matches today. Qatar face Switzerland.") do
      result = UpcomingMatchesInsightService.call([@tomorrow_match])

      assert_includes result, "Football fact:"
      assert UpcomingMatchesInsightService::FOOTBALL_FACTS.any? { |fact| result.include?(fact) },
             "expected the sign-off to be one of the curated true facts"
    end
  end

  test "the football fact is appended per render, not baked into the cached body" do
    GroqClient.stub(:call, "Real insight about Mexico vs South Africa.") do
      UpcomingMatchesInsightService.call([@tomorrow_match])
    end

    cached = AiInsightCache.find_by(key: "upcoming_matches_insight").content
    refute_includes cached, "Football fact:", "the fact must be appended after caching, so it can vary"
  end

  test "consecutive renders never repeat the same football fact" do
    GroqClient.stub(:call, "Real insight about Mexico vs South Africa.") do
      facts = 8.times.map do
        result = UpcomingMatchesInsightService.call([@tomorrow_match])
        result[/Football fact: (.+)\z/m, 1]
      end

      facts.each_cons(2) do |earlier, later|
        refute_equal earlier, later, "each render's fact must differ from the one before it"
      end
    end
  end

  test "match line adds Vietnam time when a Vietnam-based owner is involved" do
    # @tomorrow_match is Mexico (owned by Richard) vs South Africa
    prompt = UpcomingMatchesInsightService.new([@tomorrow_match]).send(:build_user_message)
    assert_includes prompt, "UK time"
    assert_includes prompt, "Vietnam time"
  end

  test "match line shows UK time only when no Vietnam-based owner is involved" do
    # @later_match is Spain vs Haiti, both unowned in this setup
    prompt = UpcomingMatchesInsightService.new([@later_match]).send(:build_user_message)
    assert_includes prompt, "UK time"
    refute_includes prompt, "Vietnam time"
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

  test "system prompt keeps the Gary Lineker voice but forbids naming the presenter in the output" do
    service = UpcomingMatchesInsightService.new([@tomorrow_match])
    prompt = service.send(:build_system_prompt, TournamentContextService.new)

    # Persona/voice stays Gary Lineker (shapes the voice only) ...
    assert_includes prompt, "Gary Lineker"
    assert_includes prompt, "Match of the Day"
    # ... but the model must never write its name in the message it produces.
    assert_includes prompt, "Never write your own name"
    # The voice changes the wording, never the facts — accuracy rules must survive
    assert_includes prompt, "HARD FACTS come ONLY from the data"
    assert_includes prompt, "ONLY discuss the matches listed"
    assert_includes prompt, "Never state or imply a different date"
  end

  test "system prompt permits brief historical colour but ring-fences the hard facts" do
    prompt = UpcomingMatchesInsightService.new([@tomorrow_match]).send(:build_system_prompt, TournamentContextService.new)

    # Colour from the model's own football knowledge is now allowed, with a guardrail
    assert_includes prompt, "COLOUR you MAY add from your own football knowledge"
    assert_includes prompt, "if unsure, leave it out"
    # ... but hard facts still come only from the data, and only listed fixtures are discussed
    assert_includes prompt, "HARD FACTS come ONLY from the data"
    assert_includes prompt, "never mention another fixture"
    # The opening-match enrichment is requested in the structure
    assert_includes prompt, "opening-match note"
  end

  test "system prompt allows grounded forecasts and table-movement framing" do
    prompt = UpcomingMatchesInsightService.new([@tomorrow_match]).send(:build_system_prompt, TournamentContextService.new)

    assert_includes prompt, "You MAY forecast"
    assert_includes prompt, "puts them top of the group"
    # Upcoming fixtures are only mentioned when flagged as a decisive final game
    assert_includes prompt, "final group game (could decide their fate)"
  end

  test "system prompt explains that group matches matter for knockout progression" do
    service = UpcomingMatchesInsightService.new([@tomorrow_match])
    prompt = service.send(:build_system_prompt, TournamentContextService.new)

    assert_match(/never call a group match meaningless or pointless/i, prompt)
    assert_match(/group win matters/i, prompt)
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
      assert result.start_with?("Real insight about Mexico vs South Africa."), "expected the generated message"
      assert_includes result, "Football fact:" # verified sign-off appended
      assert_equal 1, AiInsightCache.where(key: "upcoming_matches_insight").count
    end
  end

  test "prompt notes recently finished matches without revealing the score" do
    korea   = Team.create!(name: "Korea Republic", flag_url: "https://x.com/kr.svg")
    czechia = Team.create!(name: "Czechia", flag_url: "https://x.com/cz.svg")
    Match.create!(
      home_team: korea, away_team: czechia, stage: "Group Stage", status: "PostEvent",
      match_id: "umis-finished-1", home_score: 2, away_score: 1, winner: "home",
      start_time: Time.zone.local(2026, 6, 10, 2, 0, 0)
    )

    service = UpcomingMatchesInsightService.new([@tomorrow_match])
    prompt = service.send(:build_user_message)

    assert_includes prompt, "MATCHES ALREADY PLAYED (DO NOT REVEAL RESULTS):"
    assert_includes prompt, "Korea Republic vs Czechia — Group Stage — Wednesday 10 June 2026, 02:00 UK time"
    refute_includes prompt, "2-1", "the score must never appear in the prompt"
  end

  test "prompt omits the already-played section when nothing has finished recently" do
    service = UpcomingMatchesInsightService.new([@tomorrow_match])
    prompt = service.send(:build_user_message)

    refute_includes prompt, "MATCHES ALREADY PLAYED"
  end

  test "system prompt instructs Gary Lineker never to reveal results of already-played matches" do
    service = UpcomingMatchesInsightService.new([@tomorrow_match])
    prompt = service.send(:build_system_prompt, TournamentContextService.new)

    assert_includes prompt, "MATCHES ALREADY PLAYED"
    assert_includes prompt, "Never mention the score, goalscorers, winner, or result"
  end

  test "cache version changes when a match enters the recently-finished window" do
    # Anchor match: PostEvent, Group Stage, but well outside the 24h "recently finished"
    # window. This puts tournament_status at :group_stage for both snapshots below, so
    # the only thing that can change cache_version is recently_finished_matches.
    portugal = Team.create!(name: "Portugal", flag_url: "https://x.com/pt.svg")
    ghana    = Team.create!(name: "Ghana", flag_url: "https://x.com/gh.svg")
    Match.create!(
      home_team: portugal, away_team: ghana, stage: "Group Stage", status: "PostEvent",
      match_id: "umis-finished-old", home_score: 3, away_score: 0, winner: "home",
      start_time: Time.zone.local(2026, 6, 1, 12, 0, 0)
    )

    version_before = UpcomingMatchesInsightService.new([@tomorrow_match]).send(:cache_version)

    korea   = Team.create!(name: "Korea Republic", flag_url: "https://x.com/kr.svg")
    czechia = Team.create!(name: "Czechia", flag_url: "https://x.com/cz.svg")
    Match.create!(
      home_team: korea, away_team: czechia, stage: "Group Stage", status: "PostEvent",
      match_id: "umis-finished-2", home_score: 1, away_score: 0, winner: "home",
      start_time: Time.zone.local(2026, 6, 10, 2, 0, 0)
    )

    version_after = UpcomingMatchesInsightService.new([@tomorrow_match]).send(:cache_version)

    refute_equal version_before, version_after
  end

  test "group match user message includes factual group context, not the old one-liner" do
    service = UpcomingMatchesInsightService.new([@tomorrow_match])
    prompt = service.send(:build_user_message)

    refute_includes prompt, "no points awarded directly"
    assert_includes prompt, "Group A"
    assert_includes prompt, "What tonight's result does"
  end

  test "cache version changes when a group result lands (isolated from tournament status)" do
    # Anchor: a PostEvent group-stage match well outside the 24h recently-finished
    # window, so tournament_status is already :group_stage for BOTH snapshots below.
    # That leaves GameStateSnapshot.data_version as the only thing that can move
    # cache_version when the new result lands.
    portugal = Team.create!(name: "Portugal", flag_url: "https://x.com/pt.svg")
    ghana    = Team.create!(name: "Ghana", flag_url: "https://x.com/gh.svg")
    Match.create!(home_team: portugal, away_team: ghana, stage: "Group Stage", status: "PostEvent",
                  group_name: "Group J", match_id: "gj-anchor", home_score: 3, away_score: 0,
                  start_time: Time.zone.local(2026, 6, 1, 12, 0, 0))

    service = UpcomingMatchesInsightService.new([@tomorrow_match])
    before  = service.send(:cache_version)

    egypt  = Team.create!(name: "Egypt", flag_url: "https://x.com/eg.svg")
    sweden = Team.create!(name: "Sweden", flag_url: "https://x.com/se.svg")
    Match.create!(home_team: egypt, away_team: sweden, stage: "Group Stage", status: "PostEvent",
                  group_name: "Group K", match_id: "gk-result", home_score: 1, away_score: 0,
                  start_time: Time.zone.local(2026, 6, 2, 12, 0, 0))

    refute_equal before, service.send(:cache_version)
  end
end
