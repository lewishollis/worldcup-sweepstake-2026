require "test_helper"

class MatchInsightServiceTest < ActiveSupport::TestCase
  def setup
    @lewis = Friend.create!(name: "Lewis")
    @lewis_group = Group.create!(name: "Lewis Group", multiplier: 2.0, friend: @lewis)
    brazil = Team.create!(name: "Brazil", flag_url: "https://x.com/b.svg", points: 2, progressed: true)
    france = Team.create!(name: "France", flag_url: "https://x.com/f.svg", points: 1, progressed: true)
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

  private

  def with_env(vars, &block)
    original = vars.keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    block.call
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
