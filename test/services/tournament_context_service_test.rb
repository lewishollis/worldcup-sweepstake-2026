require "test_helper"

class TournamentContextServiceTest < ActiveSupport::TestCase
  def setup
    @lewis = Friend.create!(name: "Lewis")
    @sarah = Friend.create!(name: "Sarah")
    @lewis_group = Group.create!(name: "Lewis Group", multiplier: 2.0, friend: @lewis)
    @sarah_group = Group.create!(name: "Sarah Group", multiplier: 3.0, friend: @sarah)
    brazil = Team.create!(name: "Brazil", flag_url: "https://x.com/b.svg", points: 3, progressed: true)
    france = Team.create!(name: "France", flag_url: "https://x.com/f.svg", points: 1, progressed: true)
    @lewis_group.teams << brazil
    @sarah_group.teams << france
  end

  test "leaderboard returns friends ranked by score descending" do
    ctx = TournamentContextService.new
    lb = ctx.leaderboard
    assert_equal "Lewis", lb.first[:friend]   # 3 × 2 = 6
    assert_equal "Sarah", lb.last[:friend]    # 1 × 3 = 3
    assert_equal 6.0, lb.first[:score]
    assert_equal 3.0, lb.last[:score]
  end

  test "leaderboard includes rank" do
    ctx = TournamentContextService.new
    lb = ctx.leaderboard
    assert_equal 1, lb.first[:rank]
    assert_equal 2, lb.last[:rank]
  end

  test "leaderboard_text formats standings as readable string" do
    ctx = TournamentContextService.new
    text = ctx.leaderboard_text
    assert_includes text, "1. Lewis"
    assert_includes text, "2. Sarah"
  end

  test "news_items returns empty array when no news exists" do
    ctx = TournamentContextService.new
    assert_equal [], ctx.news_items(limit: 3)
  end
end
