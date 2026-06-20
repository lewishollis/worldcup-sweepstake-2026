# test/services/qualification_status_test.rb
require "test_helper"

class QualificationStatusTest < ActiveSupport::TestCase
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

  test "clinched team is :through, eliminated team is :out" do
    a, b, c, d = team("Aa"), team("Bb"), team("Cc"), team("Dd")
    match("G1", a, b, status: "PostEvent", hs: 1, as: 0)
    match("G1", a, c, status: "PostEvent", hs: 1, as: 0)
    match("G1", a, d, status: "PostEvent", hs: 1, as: 0) # Aa 9
    match("G1", b, c, status: "PostEvent", hs: 1, as: 0)
    match("G1", b, d, status: "PostEvent", hs: 1, as: 0) # Bb 6
    match("G1", c, d, status: "PostEvent", hs: 1, as: 0) # Cc 3, Dd 0

    assert_equal :through, status_for("G1", a)
    assert_equal :through, status_for("G1", b)
    assert_equal :out,     status_for("G1", c)
    assert_equal :out,     status_for("G1", d)
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

  test "label maps each key to its display string" do
    assert_equal "Through",       QualificationStatus.label(:through)
    assert_equal "Likely",        QualificationStatus.label(:likely)
    assert_equal "Out",           QualificationStatus.label(:out)
    assert_equal "In the mix",    QualificationStatus.label(:contention)
  end
end
