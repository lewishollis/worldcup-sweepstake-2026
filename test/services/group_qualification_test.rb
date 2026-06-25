require "test_helper"

class GroupQualificationTest < ActiveSupport::TestCase
  def team(name)
    Team.create!(name: name, flag_url: "https://x.com/#{name}.svg")
  end

  def match(group, home, away, status:, hs: nil, as: nil, mid: nil)
    Match.create!(home_team: home, away_team: away, stage: "Group Stage", status: status,
                  group_name: group, match_id: mid || "gq-#{home.name}-#{away.name}",
                  home_score: hs, away_score: as,
                  start_time: Time.zone.local(2026, 6, 13, 17, 0, 0))
  end

  # Group with all 6 matches played: top 2 are mathematically settled.
  test "settled group: top two clinched, bottom two cannot finish top 2" do
    a, b, c, d = team("Aa"), team("Bb"), team("Cc"), team("Dd")
    match("G1", a, b, status: "PostEvent", hs: 1, as: 0)
    match("G1", a, c, status: "PostEvent", hs: 1, as: 0)
    match("G1", a, d, status: "PostEvent", hs: 1, as: 0) # Aa 9
    match("G1", b, c, status: "PostEvent", hs: 1, as: 0)
    match("G1", b, d, status: "PostEvent", hs: 1, as: 0) # Bb 6
    match("G1", c, d, status: "PostEvent", hs: 1, as: 0) # Cc 3, Dd 0

    table = GroupTable.new("G1", Match.where(group_name: "G1").to_a)
    gq = GroupQualification.new(table)
    assert_equal :clinched_top2,      gq.flag(a)
    assert_equal :clinched_top2,      gq.flag(b)
    assert_equal :cannot_finish_top2, gq.flag(c)
    assert_equal :cannot_finish_top2, gq.flag(d)
  end

  # After 2 rounds, leader on 6 with one to play is mathematically safe;
  # bottom team on 0 with one to play cannot reach top 2.
  test "clinch and eliminate with one round remaining" do
    a, b, c, d = team("Pp"), team("Qq"), team("Rr"), team("Ss")
    # Round 1
    match("G2", a, b, status: "PostEvent", hs: 1, as: 0, mid: "g2-ab")
    match("G2", c, d, status: "PostEvent", hs: 1, as: 0, mid: "g2-cd")
    # Round 2
    match("G2", a, c, status: "PostEvent", hs: 1, as: 0, mid: "g2-ac") # Pp 6, Rr 3
    match("G2", b, d, status: "PostEvent", hs: 1, as: 0, mid: "g2-bd") # Qq 3, Ss 0
    # Round 3 remaining: Pp v Ss, Qq v Rr
    match("G2", a, d, status: "PreEvent", mid: "g2-ad")
    match("G2", b, c, status: "PreEvent", mid: "g2-bc")

    table = GroupTable.new("G2", Match.where(group_name: "G2").to_a)
    gq = GroupQualification.new(table)
    # Pp on 6: best others can reach is 6 (Qq or Rr), but at most one of them can,
    # so Pp is guaranteed top 2.
    assert_equal :clinched_top2,      gq.flag(a)
    # Ss on 0 with one game: max 3, but Pp(6) and one of Qq/Rr finish above → out.
    assert_equal :cannot_finish_top2, gq.flag(d)
    # Qq and Rr are still fighting for the 2nd spot.
    assert_equal :in_contention,      gq.flag(b)
    assert_equal :in_contention,      gq.flag(c)
  end

  # cannot_reach_knockouts? proves a team is out of BOTH the top-2 AND the
  # best-third path — i.e. mathematically locked into last place (4th) in every
  # completion. Finishing 3rd keeps the best-third door open, so it is NOT "out".
  test "settled group: only the last-placed team cannot reach the knockouts" do
    a, b, c, d = team("Aa"), team("Bb"), team("Cc"), team("Dd")
    match("G1", a, b, status: "PostEvent", hs: 1, as: 0)
    match("G1", a, c, status: "PostEvent", hs: 1, as: 0)
    match("G1", a, d, status: "PostEvent", hs: 1, as: 0) # Aa 9
    match("G1", b, c, status: "PostEvent", hs: 1, as: 0)
    match("G1", b, d, status: "PostEvent", hs: 1, as: 0) # Bb 6
    match("G1", c, d, status: "PostEvent", hs: 1, as: 0) # Cc 3, Dd 0

    gq = GroupQualification.new(GroupTable.new("G1", Match.where(group_name: "G1").to_a))
    refute gq.cannot_reach_knockouts?(a), "1st can reach the knockouts"
    refute gq.cannot_reach_knockouts?(b), "2nd can reach the knockouts"
    refute gq.cannot_reach_knockouts?(c), "3rd is alive via the best-third route"
    assert gq.cannot_reach_knockouts?(d), "last place is out of every path"
  end

  # A team that cannot finish top 2 but can still finish 3rd is NOT out of the
  # knockouts — the best-third route remains mathematically open.
  test "can-still-finish-3rd team is not eliminated even when top 2 is gone" do
    a, b, c, d = team("Pp"), team("Qq"), team("Rr"), team("Ss")
    match("G2", a, b, status: "PostEvent", hs: 1, as: 0, mid: "g2-ab")
    match("G2", c, d, status: "PostEvent", hs: 1, as: 0, mid: "g2-cd")
    match("G2", a, c, status: "PostEvent", hs: 1, as: 0, mid: "g2-ac") # Pp 6, Rr 3
    match("G2", b, d, status: "PostEvent", hs: 1, as: 0, mid: "g2-bd") # Qq 3, Ss 0
    match("G2", a, d, status: "PreEvent", mid: "g2-ad")
    match("G2", b, c, status: "PreEvent", mid: "g2-bc")

    gq = GroupQualification.new(GroupTable.new("G2", Match.where(group_name: "G2").to_a))
    # Ss on 0: cannot finish top 2, but a win (→3) ties Rr/Qq for 3rd, so the
    # best-third route is still open → not eliminated.
    assert_equal :cannot_finish_top2, gq.flag(d)
    refute gq.cannot_reach_knockouts?(d)
  end

  test "effects report the resulting group position (a win goes top)" do
    a, b, c, d = team("Aaa"), team("Bbb"), team("Ccc"), team("Ddd")
    match("GP", a, c, status: "PostEvent", hs: 1, as: 0, mid: "gp-ac") # Aaa 3
    match("GP", b, d, status: "PostEvent", hs: 1, as: 0, mid: "gp-bd") # Bbb 3
    upcoming = match("GP", a, b, status: "PreEvent", mid: "gp-ab")
    match("GP", c, d, status: "PreEvent", mid: "gp-cd")

    gq  = GroupQualification.new(GroupTable.new("GP", Match.where(group_name: "GP").to_a))
    eff = gq.effects(upcoming)

    assert_equal 1, eff[:home_win][:home][:position] # Aaa win -> top of the group
    assert_equal 2, eff[:away_win][:home][:position] # Bbb win -> Aaa drops to 2nd
  end

  test "effects: a win clinches top 2 for a contender" do
    a, b, c, d = team("Tt"), team("Uu"), team("Vv"), team("Ww")
    match("G3", a, b, status: "PostEvent", hs: 1, as: 0, mid: "g3-ab")
    match("G3", c, d, status: "PostEvent", hs: 1, as: 0, mid: "g3-cd")
    match("G3", a, c, status: "PostEvent", hs: 1, as: 0, mid: "g3-ac") # Tt 6, Vv 3
    match("G3", b, d, status: "PostEvent", hs: 1, as: 0, mid: "g3-bd") # Uu 3, Ww 0
    upcoming = match("G3", b, c, status: "PreEvent", mid: "g3-bc") # Uu(3) v Vv(3)
    match("G3", a, d, status: "PreEvent", mid: "g3-ad")

    table = GroupTable.new("G3", Match.where(group_name: "G3").to_a)
    gq = GroupQualification.new(table)
    effects = gq.effects(upcoming)

    # If Uu wins it reaches 6: Tt(>=6) and Uu top 2 regardless of Tt v Ww → clinched.
    assert_equal :clinched_top2, effects[:home_win][:home][:flag]
    assert_equal b, effects[:home_win][:home][:team]
  end
end
