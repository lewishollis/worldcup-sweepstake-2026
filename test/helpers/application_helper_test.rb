require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  def team(name)
    Team.create!(name: name, flag_url: "https://x.com/#{name}.svg")
  end

  def match(group, home, away, hs, as)
    Match.create!(home_team: home, away_team: away, stage: "Group Stage", status: "PostEvent",
                  group_name: group, match_id: "ah-#{home.name}-#{away.name}",
                  home_score: hs, away_score: as,
                  start_time: Time.zone.local(2026, 6, 13, 17, 0, 0))
  end

  test "returns the qualification status for a grouped team" do
    a, b, c, d = team("Aa"), team("Bb"), team("Cc"), team("Dd")
    match("G1", a, b, 1, 0); match("G1", a, c, 1, 0); match("G1", a, d, 1, 0)
    match("G1", b, c, 1, 0); match("G1", b, d, 1, 0); match("G1", c, d, 1, 0)

    assert_equal :through, team_qualification_status(a)
    assert_equal :out,     team_qualification_status(d)
  end

  test "returns nil for a team in no group-stage table" do
    loner = team("Zz")
    assert_nil team_qualification_status(loner)
  end

  test "vietnam_kickoff converts UK kick-off to UTC+7" do
    # 14:00 BST = 13:00 UTC = 20:00 in Vietnam, same date
    kickoff = Time.zone.local(2026, 6, 13, 14, 0, 0)
    assert_equal "20:00", vietnam_kickoff(kickoff)
  end

  test "vietnam_kickoff flags the next day when the date rolls over" do
    # 20:00 BST on Thu 11 Jun = 02:00 on Fri 12 Jun in Vietnam
    kickoff = Time.zone.local(2026, 6, 11, 20, 0, 0)
    assert_equal "02:00 Fri", vietnam_kickoff(kickoff)
  end

  test "vietnam_kickoff handles nil" do
    assert_nil vietnam_kickoff(nil)
  end
end
