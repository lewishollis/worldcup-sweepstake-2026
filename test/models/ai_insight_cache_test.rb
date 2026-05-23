require "test_helper"

class AiInsightCacheTest < ActiveSupport::TestCase
  test "fetch returns nil when no record exists" do
    assert_nil AiInsightCache.fetch(key: "leaderboard", version: "abc123")
  end

  test "fetch returns nil when version does not match" do
    AiInsightCache.create!(key: "leaderboard", content: "Old insight", version: "old", generated_at: Time.current)
    assert_nil AiInsightCache.fetch(key: "leaderboard", version: "new")
  end

  test "fetch returns content when version matches" do
    AiInsightCache.create!(key: "leaderboard", content: "Current insight", version: "v1", generated_at: Time.current)
    assert_equal "Current insight", AiInsightCache.fetch(key: "leaderboard", version: "v1")
  end

  test "store creates new record" do
    assert_difference "AiInsightCache.count", 1 do
      AiInsightCache.store(key: "leaderboard", version: "v1", content: "Fresh insight")
    end
  end

  test "store updates existing record" do
    AiInsightCache.create!(key: "leaderboard", content: "Old", version: "v1", generated_at: Time.current)
    assert_no_difference "AiInsightCache.count" do
      AiInsightCache.store(key: "leaderboard", version: "v2", content: "New")
    end
    assert_equal "New", AiInsightCache.find_by(key: "leaderboard").content
  end
end
