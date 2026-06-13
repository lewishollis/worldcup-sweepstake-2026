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
    # Qatar and Switzerland have no group games left after tonight, so the
    # (decluttering) run-in line is omitted — it only appears when pivotal.
    refute_includes text, "final group game"
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

  test "group context shows favourites, table movement, and the run-in" do
    strong = Team.create!(name: "Strongteam", flag_url: "https://x.com/s.svg"); strong.update_column(:fifa_rank, 5)
    mid    = Team.create!(name: "Midteam",    flag_url: "https://x.com/m.svg"); mid.update_column(:fifa_rank, 30)
    weak   = Team.create!(name: "Weakteam",   flag_url: "https://x.com/w.svg"); weak.update_column(:fifa_rank, 60)
    other  = Team.create!(name: "Otherteam",  flag_url: "https://x.com/o.svg"); other.update_column(:fifa_rank, 80)

    g = lambda do |id, home, away, status, hs = nil, as = nil, day = 18|
      Match.create!(home_team: home, away_team: away, stage: "Group Stage", status: status,
                    group_name: "GZ", match_id: id, home_score: hs, away_score: as,
                    start_time: Time.zone.local(2026, 6, day, 17, 0, 0))
    end
    g.call("gz-wo", weak, other, "PostEvent", 1, 1)          # both on 1pt
    tonight = g.call("gz-sm", strong, mid, "PreEvent", nil, nil, 14)
    g.call("gz-sw", strong, weak, "PreEvent", nil, nil, 18)  # Strongteam's run-in
    g.call("gz-mo", mid, other, "PreEvent", nil, nil, 18)    # Midteam's run-in

    text = GameStateSnapshot.new.group_context_text(tonight)
    assert_includes text, "Group favourites"
    assert_includes text, "Strongteam (world #5)"
    assert_includes text, "top of the group"                 # a win sends them top
    # Strongteam has one group game left after tonight and is in contention, so the
    # pivotal final-game line is surfaced.
    assert_includes text, "final group game (could decide their fate)"
    assert_includes text, "vs Weakteam (world #60)"
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
