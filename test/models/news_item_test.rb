require "test_helper"

class NewsItemTest < ActiveSupport::TestCase
  test "requires guid" do
    item = NewsItem.new(title: "Test", published_at: Time.current)
    assert_not item.valid?
    assert_includes item.errors[:guid], "can't be blank"
  end

  test "requires title" do
    item = NewsItem.new(guid: "abc-123", published_at: Time.current)
    assert_not item.valid?
    assert_includes item.errors[:title], "can't be blank"
  end

  test "enforces unique guid" do
    NewsItem.create!(guid: "dup-1", title: "First", published_at: 1.hour.ago)
    duplicate = NewsItem.new(guid: "dup-1", title: "Second", published_at: Time.current)
    assert_not duplicate.valid?
  end

  test "recent scope orders by published_at descending" do
    older = NewsItem.create!(guid: "old-1", title: "Old", published_at: 2.days.ago)
    newer = NewsItem.create!(guid: "new-1", title: "New", published_at: 1.hour.ago)
    assert_equal newer, NewsItem.recent.first
  end
end
