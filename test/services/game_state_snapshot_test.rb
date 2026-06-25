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

  # Regression: Qatar and Switzerland are BOTH on 6pts and have already clinched
  # top 2 before tonight's match. The result cannot bank either owner a +1 — it
  # only decides seeding. The snapshot must not frame the +1 as still at stake,
  # or the AI writes "a Qatar win banks Ben's +1" for an already-secured point.
  test "already-clinched teams: result only affects seeding, the +1 is not at stake" do
    text = GameStateSnapshot.new.group_context_text(@upcoming)
    refute_includes text, "banks +1"
    assert_match(/already (through|secured)/i, text)
    assert_match(/seeding/i, text)
  end

  test "an outcome that newly clinches a contender still banks the +1" do
    lead  = Team.create!(name: "Leadteam",  flag_url: "https://x.com/l.svg")
    push  = Team.create!(name: "Pushteam",  flag_url: "https://x.com/p.svg")
    rival = Team.create!(name: "Rivalteam", flag_url: "https://x.com/r.svg")
    base  = Team.create!(name: "Baseteam",  flag_url: "https://x.com/b.svg")
    Group.create!(name: "GC owner", friend: @ben).teams << push

    g = lambda do |id, home, away, status, hs = nil, as = nil|
      Match.create!(home_team: home, away_team: away, stage: "Group Stage", status: status,
                    group_name: "GC", match_id: id, home_score: hs, away_score: as,
                    start_time: Time.zone.local(2026, 6, 18, 17, 0, 0))
    end
    g.call("gc-1", lead, push,  "PostEvent", 1, 0)
    g.call("gc-2", rival, base, "PostEvent", 1, 0)
    g.call("gc-3", lead, rival, "PostEvent", 1, 0) # Leadteam 6, Rivalteam 3
    g.call("gc-4", push, base,  "PostEvent", 1, 0) # Pushteam 3, Baseteam 0
    tonight = g.call("gc-5", push, rival, "PreEvent") # Pushteam(3) v Rivalteam(3)
    g.call("gc-6", lead, base, "PreEvent")

    text = GameStateSnapshot.new.group_context_text(tonight)
    # A Pushteam win reaches 6 and clinches top 2 (was only in contention) — that
    # genuinely banks the +1, so the causal phrasing is correct here.
    assert_includes text, "banks +1"
  end

  # A team out of the top 2 is NOT necessarily out: the best third-placed teams
  # also advance. Brazil and Morocco (0pts) can't finish top 2 — Qatar and
  # Switzerland have clinched — but a win still reaches 3rd, so the best-third
  # route is open. The standings must say so, not imply they're done.
  test "standings show best-third hope for a team out of the top 2 but able to reach 3rd" do
    text = GameStateSnapshot.new.group_context_text(@upcoming)
    assert_includes text, "alive for a best-third place"
  end

  test "result lines flag a best-third hope when a win lifts a team to 3rd" do
    brazil_v_morocco = Match.find_by(match_id: "gb-6")
    text = GameStateSnapshot.new.group_context_text(brazil_v_morocco)
    assert_includes text, "alive for a best-third place"
  end

  # A team that cannot reach even 3rd in any completion is genuinely out — the
  # label must say so, not offer a best-third hope it doesn't have.
  test "standings mark a team out of every route as fully out" do
    a, b, c, d = %w[Aaa Bbb Ccc Ddd].map { |n| Team.create!(name: n, flag_url: "https://x.com/#{n}.svg") }
    g = lambda do |id, home, away, status, hs = nil, as = nil|
      Match.create!(home_team: home, away_team: away, stage: "Group Stage", status: status,
                    group_name: "GE", match_id: id, home_score: hs, away_score: as,
                    start_time: Time.zone.local(2026, 6, 18, 17, 0, 0))
    end
    g.call("ge-ad", a, d, "PostEvent", 1, 0)
    g.call("ge-bd", b, d, "PostEvent", 1, 0)
    g.call("ge-cd", c, d, "PostEvent", 1, 0) # Ddd 0, played all 3 → out
    g.call("ge-ab", a, b, "PostEvent", 1, 0)
    tonight = g.call("ge-ac", a, c, "PreEvent")
    g.call("ge-bc", b, c, "PreEvent")

    text = GameStateSnapshot.new.group_context_text(tonight)
    assert_includes text, "cannot finish top 2 or reach a best-third place"
    refute_includes text, "Ddd 0pts (GD -3) — cannot finish top 2, but still alive"
  end

  test "group context flags an opening match when neither side has played yet" do
    spain = Team.create!(name: "Spain", flag_url: "https://x.com/es.svg")
    fiji  = Team.create!(name: "Fiji",  flag_url: "https://x.com/fj.svg")
    peru  = Team.create!(name: "Peru",  flag_url: "https://x.com/pe.svg")
    iran  = Team.create!(name: "Iran",  flag_url: "https://x.com/ir.svg")

    opener = Match.create!(home_team: spain, away_team: fiji, stage: "Group Stage",
                           status: "PreEvent", group_name: "Group Z", match_id: "gz-open",
                           start_time: Time.zone.local(2026, 6, 13, 17, 0, 0))
    Match.create!(home_team: peru, away_team: iran, stage: "Group Stage",
                  status: "PreEvent", group_name: "Group Z", match_id: "gz-other",
                  start_time: Time.zone.local(2026, 6, 13, 20, 0, 0))

    text = GameStateSnapshot.new.group_context_text(opener)
    assert_includes text, "opening Group Z match for both Spain and Fiji"
  end

  test "group context omits the opening-match note once both sides have played" do
    # Qatar and Switzerland have each played two games in the setup.
    text = GameStateSnapshot.new.group_context_text(@upcoming)
    refute_includes text, "opening"
  end

  test "a result that leaves teams level at the top says so on points, not vaguely" do
    # Qatar and Switzerland both sit on 6pts, so a draw keeps them joint top.
    text = GameStateSnapshot.new.group_context_text(@upcoming)
    assert_includes text, "level on points at the top of the group"
    refute_includes text, "among the group leaders"
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
    # Strongteam is still in contention, so the live chance to qualify is spelled out.
    assert_includes text, "still in with a chance of going through"
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
