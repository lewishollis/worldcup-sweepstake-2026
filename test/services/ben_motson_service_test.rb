require "test_helper"

class BenMotsonServiceTest < ActiveSupport::TestCase
  def setup
    @lewis = Friend.create!(name: "Lewis")
    @sarah = Friend.create!(name: "Sarah")
    @lewis_group = Group.create!(name: "Lewis Group", friend: @lewis)
    @sarah_group = Group.create!(name: "Sarah Group", friend: @sarah)
    brazil = Team.create!(name: "Brazil", flag_url: "https://x.com/b.svg")
    france = Team.create!(name: "France", flag_url: "https://x.com/f.svg")
    @lewis_group.teams << brazil
    @sarah_group.teams << france
    Match.create!(home_team: brazil, away_team: france, stage: "Semi-finals",
                  status: "PreEvent", match_id: "bms-1", home_score: 0, away_score: 0)
  end

  test "leaderboard insight returns string when Groq unavailable" do
    with_env("GROQ_API_KEY" => nil) do
      result = BenBotcurdyService.new(:leaderboard).generate_insight
      assert_kind_of String, result
      assert result.length > 0
    end
  end

  test "leaderboard insight uses Groq response when available" do
    GroqClient.stub(:call, "Lewis dominates at the top!") do
      result = BenBotcurdyService.new(:leaderboard).generate_insight
      assert_equal "Lewis dominates at the top!", result
    end
  end

  test "matches insight returns string" do
    match = Match.first
    result = BenBotcurdyService.new(:matches, { matches: [match], filter_type: "PreEvent" }).generate_insight
    assert_kind_of String, result
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
