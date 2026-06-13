require "test_helper"

class MatchInsightServiceTest < ActiveSupport::TestCase
  def setup
    @lewis = Friend.create!(name: "Lewis")
    @lewis_group = Group.create!(name: "Lewis Group", friend: @lewis)
    brazil = Team.create!(name: "Brazil", flag_url: "https://x.com/b.svg")
    france = Team.create!(name: "France", flag_url: "https://x.com/f.svg")
    @lewis_group.teams << brazil
    @match = Match.create!(
      home_team: brazil, away_team: france,
      stage: "Quarter-finals", status: "PreEvent",
      match_id: "mi-test-1", home_score: 0, away_score: 0
    )
  end

  test "returns fallback text when Groq is unavailable" do
    with_env("GROQ_API_KEY" => nil) do
      result = MatchInsightService.new(@match).call
      assert_kind_of String, result
      assert result.length > 0
    end
  end

  test "returns Groq response when API available" do
    GroqClient.stub(:call, "Brazil win puts Lewis top!") do
      result = MatchInsightService.new(@match).call
      assert_equal "Brazil win puts Lewis top!", result
    end
  end

  test "falls back gracefully when Groq returns nil" do
    GroqClient.stub(:call, nil) do
      result = MatchInsightService.new(@match).call
      assert_kind_of String, result
    end
  end

  test "group-stage preview user message includes factual group context" do
    home = Team.create!(name: "Qatar", flag_url: "https://x.com/qa.svg")
    away = Team.create!(name: "Switzerland", flag_url: "https://x.com/ch.svg")
    Match.create!(home_team: home, away_team: away, stage: "Group Stage", status: "PostEvent",
                  group_name: "Group B", match_id: "mi-played", home_score: 1, away_score: 0,
                  start_time: Time.zone.local(2026, 6, 13, 17, 0, 0))
    upcoming = Match.create!(home_team: home, away_team: away, stage: "Group Stage", status: "PreEvent",
                             group_name: "Group B", match_id: "mi-upcoming",
                             start_time: Time.zone.local(2026, 6, 17, 17, 0, 0))

    msg = MatchInsightService.new(upcoming).send(:build_user_message)
    assert_includes msg, "Group B"
    assert_includes msg, "What tonight's result does"
  end

  private

  def with_env(vars, &block)
    original = vars.keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    block.call
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
