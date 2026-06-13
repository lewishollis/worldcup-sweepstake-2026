require "test_helper"

class GameStateSnapshotTest < ActiveSupport::TestCase
  def setup
    @ben   = Friend.create!(name: "Ben")
    @nhien = Friend.create!(name: "Nhiên")
    @qatar = Team.create!(name: "Qatar", flag_url: "https://x.com/qa.svg")
    @swiss = Team.create!(name: "Switzerland", flag_url: "https://x.com/ch.svg")
    @brazil = Team.create!(name: "Brazil", flag_url: "https://x.com/br.svg")
    @morocco = Team.create!(name: "Morocco", flag_url: "https://x.com/ma.svg")
    Group.create!(name: "Group 3", friend: @ben).teams << @qatar
    Group.create!(name: "Group 9", friend: @nhien).teams << @swiss

    # Two rounds played in Group B
    mk("gb-1", @swiss, @morocco, "PostEvent", 2, 0)
    mk("gb-2", @qatar, @brazil, "PostEvent", 1, 0)
    mk("gb-3", @swiss, @brazil, "PostEvent", 2, 0)   # Switzerland 6
    mk("gb-4", @qatar, @morocco, "PostEvent", 1, 0)  # Qatar 6
    # Upcoming final round
    @upcoming = mk("gb-5", @qatar, @swiss, "PreEvent")
    mk("gb-6", @brazil, @morocco, "PreEvent")
  end

  def mk(id, home, away, status, hs = nil, as = nil)
    Match.create!(home_team: home, away_team: away, stage: "Group Stage", status: status,
                  group_name: "Group B", match_id: id, home_score: hs, away_score: as,
                  start_time: Time.zone.local(2026, 6, 13, 20, 0, 0))
  end

  test "group_context_text names only the group's teams, with owners" do
    text = GameStateSnapshot.new.group_context_text(@upcoming)
    assert_includes text, "Group B"
    assert_includes text, "Qatar"
    assert_includes text, "Switzerland"
    assert_includes text, "Ben"      # Qatar's owner
    assert_includes text, "Nhiên"    # Switzerland's owner
    refute_includes text, "England"  # never drag in teams outside the group
  end

  test "group_context_text states what each result means and the points reminder" do
    text = GameStateSnapshot.new.group_context_text(@upcoming)
    assert_includes text, "If Qatar win"
    assert_includes text, "If Switzerland win"
    assert_match(/\+1/, text) # qualifying-point reminder
  end

  test "world rankings appear in the group table and team summary when known" do
    @qatar.update_column(:fifa_rank, 56)
    @swiss.update_column(:fifa_rank, 19)

    snapshot = GameStateSnapshot.new
    table_text = snapshot.group_context_text(@upcoming)
    assert_includes table_text, "world #56" # Qatar
    assert_includes table_text, "world #19" # Switzerland

    summary = snapshot.team_group_summary(@qatar)
    assert_includes summary, "Qatar (world #56)"
    assert_includes summary, "Group rivals:"
    assert_includes summary, "Switzerland (world #19)"
  end

  test "team summary omits the ranking when none is stored" do
    summary = GameStateSnapshot.new.team_group_summary(@qatar) # no fifa_rank set
    assert_includes summary, "Qatar are"
    refute_includes summary, "world #"
  end

  test "group_context_text is nil for knockout matches" do
    ko = Match.create!(home_team: @qatar, away_team: @swiss, stage: "Last 32", status: "PreEvent",
                       match_id: "ko-1", start_time: Time.zone.local(2026, 7, 1, 20, 0, 0))
    assert_nil GameStateSnapshot.new.group_context_text(ko)
  end

  test "data_version changes when a group result lands" do
    before = GameStateSnapshot.data_version
    Match.find_by(match_id: "gb-5").update!(status: "PostEvent", home_score: 1, away_score: 1)
    refute_equal before, GameStateSnapshot.data_version
  end
end
