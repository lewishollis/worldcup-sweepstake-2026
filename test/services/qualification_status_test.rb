# test/services/qualification_status_test.rb
require "test_helper"

class QualificationStatusTest < ActiveSupport::TestCase
  # KnockoutQualification memoizes its clinched set by GameStateSnapshot.data_version
  # (a hash of group-stage results). Two tests here share an identical group-stage
  # signature, so without this reset the second would read a stale set keyed to the
  # first test's already-rolled-back team ids.
  setup { KnockoutQualification.reset! }

  def team(name)
    Team.create!(name: name, flag_url: "https://x.com/#{name}.svg")
  end

  def match(group, home, away, status:, hs: nil, as: nil)
    Match.create!(home_team: home, away_team: away, stage: "Group Stage", status: status,
                  group_name: group, match_id: "qs-#{home.name}-#{away.name}",
                  home_score: hs, away_score: as,
                  start_time: Time.zone.local(2026, 6, 13, 17, 0, 0))
  end

  def status_for(group, t)
    table = GroupTable.new(group, Match.where(group_name: group).to_a)
    QualificationStatus.for(t, table: table, qualification: GroupQualification.new(table))
  end

  # Regression: Group G after matchday 1 had all four teams on 1 point, GD 0,
  # separated only by goals scored. The top two on goals-for must NOT read as
  # :likely — level on points means nobody has a qualifying cushion yet.
  test "teams level on points are :contention, not :likely when separated only by goals" do
    a, b, c, d = team("Aa"), team("Bb"), team("Cc"), team("Dd")
    match("G3", a, b, status: "PostEvent", hs: 1, as: 1) # both 1pt, GF1
    match("G3", c, d, status: "PostEvent", hs: 2, as: 2) # both 1pt, GF2 (sorted above on goals)
    match("G3", a, c, status: "PreEvent")
    match("G3", a, d, status: "PreEvent")
    match("G3", b, c, status: "PreEvent")
    match("G3", b, d, status: "PreEvent")

    assert_equal :contention, status_for("G3", a)
    assert_equal :contention, status_for("G3", b)
    assert_equal :contention, status_for("G3", c)
    assert_equal :contention, status_for("G3", d)
  end

  # Settled group: top 2 are Through. The 3rd-placed team is NOT out — the best
  # third-placed teams (8 of the 12 across all groups) still advance, so it reads
  # as :third_hope. Only the last-placed team, out of every path, is :out.
  test "settled group: top 2 Through, 3rd is :third_hope, last is :out" do
    a, b, c, d = team("Aa"), team("Bb"), team("Cc"), team("Dd")
    match("G1", a, b, status: "PostEvent", hs: 1, as: 0)
    match("G1", a, c, status: "PostEvent", hs: 1, as: 0)
    match("G1", a, d, status: "PostEvent", hs: 1, as: 0) # Aa 9
    match("G1", b, c, status: "PostEvent", hs: 1, as: 0)
    match("G1", b, d, status: "PostEvent", hs: 1, as: 0) # Bb 6
    match("G1", c, d, status: "PostEvent", hs: 1, as: 0) # Cc 3, Dd 0

    assert_equal :through,     status_for("G1", a)
    assert_equal :through,     status_for("G1", b)
    assert_equal :third_hope,  status_for("G1", c)
    assert_equal :out,         status_for("G1", d)
  end

  # A team mathematically out of the top 2 but still able to finish 3rd is
  # :third_hope, not :out — its only remaining route is the best-third path.
  test "top-2 gone but 3rd still reachable is :third_hope" do
    a, b, c, d = team("Pp"), team("Qq"), team("Rr"), team("Ss")
    match("G4", a, b, status: "PostEvent", hs: 1, as: 0)
    match("G4", c, d, status: "PostEvent", hs: 1, as: 0)
    match("G4", a, c, status: "PostEvent", hs: 1, as: 0) # Pp 6, Rr 3
    match("G4", b, d, status: "PostEvent", hs: 1, as: 0) # Qq 3, Ss 0
    match("G4", a, d, status: "PreEvent")
    match("G4", b, c, status: "PreEvent")

    # Ss (0pts) cannot finish top 2, but a win ties it for 3rd → :third_hope.
    assert_equal :third_hope, status_for("G4", d)
  end

  test "top-2-on-goal-difference but not points-clinched is :likely, 3rd is :contention" do
    # One match played in an otherwise-open group: Bb beat Cc heavily and sits 2nd
    # on the live table, but nothing is mathematically clinched yet.
    a, b, c, d = team("Aa"), team("Bb"), team("Cc"), team("Dd")
    match("G2", a, d, status: "PostEvent", hs: 3, as: 0) # Aa 3pts, GD +3
    match("G2", b, c, status: "PostEvent", hs: 5, as: 0) # Bb 3pts, GD +5
    # Remaining group fixtures — unplayed, so the oracle treats the group as live:
    match("G2", a, b, status: "PreEvent")
    match("G2", a, c, status: "PreEvent")
    match("G2", b, d, status: "PreEvent")
    match("G2", c, d, status: "PreEvent")

    # Aa and Bb both 3pts; ordered by GD -> Bb 1st, Aa 2nd. Both top-2, neither clinched.
    assert_equal :likely,     status_for("G2", a)
    assert_equal :likely,     status_for("G2", b)
    # Cc lost heavily (0pts, GD -5) and Dd (0pts, GD -3) sit 3rd/4th, still alive.
    assert_equal :contention, status_for("G2", c)
    assert_equal :contention, status_for("G2", d)
  end

  # Regression: a best-third-placed team that has actually been drawn into the
  # knockouts (a real Last-32 fixture exists, so Team#progressed? is true and the
  # "Advanced" pill shows) must NOT still read as :third_hope. The badge has to
  # agree with the pill — it's :through.
  test "best-third qualifier with a knockout fixture is :through, not :third_hope" do
    a, b, c, d = team("Aa"), team("Bb"), team("Cc"), team("Dd")
    match("G1", a, b, status: "PostEvent", hs: 1, as: 0)
    match("G1", a, c, status: "PostEvent", hs: 1, as: 0)
    match("G1", a, d, status: "PostEvent", hs: 1, as: 0) # Aa 9
    match("G1", b, c, status: "PostEvent", hs: 1, as: 0)
    match("G1", b, d, status: "PostEvent", hs: 1, as: 0) # Bb 6
    match("G1", c, d, status: "PostEvent", hs: 1, as: 0) # Cc 3, Dd 0

    # Cc finished 3rd but has been drawn into the Last 32 as a best third.
    Match.create!(home_team: c, away_team: a, stage: "Last 32", status: "PreEvent",
                  match_id: "ko-cc", start_time: Time.zone.local(2026, 7, 1, 17, 0, 0))

    assert_equal :through, status_for("G1", c)
  end

  test "label maps each key to its display string" do
    assert_equal "Through",       QualificationStatus.label(:through)
    assert_equal "Likely",        QualificationStatus.label(:likely)
    assert_equal "3rd-place hope", QualificationStatus.label(:third_hope)
    assert_equal "Out",           QualificationStatus.label(:out)
    assert_equal "In the mix",    QualificationStatus.label(:contention)
  end
end
