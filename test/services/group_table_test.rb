require "test_helper"

class GroupTableTest < ActiveSupport::TestCase
  def team(name)
    Team.create!(name: name, flag_url: "https://x.com/#{name}.svg")
  end

  def played(group, home, away, hs, as)
    Match.create!(home_team: home, away_team: away, stage: "Group Stage",
                  status: "PostEvent", group_name: group,
                  match_id: "gt-#{home.name}-#{away.name}", home_score: hs, away_score: as,
                  start_time: Time.zone.local(2026, 6, 11, 18, 0, 0))
  end

  test "orders by points then goal difference then goals for" do
    a, b, c, d = team("Alpha"), team("Bravo"), team("Charlie"), team("Delta")
    played("Group Z", a, b, 3, 0)   # Alpha win, GD +3
    played("Group Z", c, d, 1, 0)   # Charlie win, GD +1
    played("Group Z", a, c, 2, 2)   # draw
    played("Group Z", b, d, 2, 2)   # draw

    table = GroupTable.new("Group Z", Match.where(group_name: "Group Z").to_a)
    names = table.rows.map { |r| r.team.name }

    # Alpha: 4pts GD+3 ; Charlie: 4pts GD+1 ; Bravo: 1pt ; Delta: 1pt GD-1 vs Bravo GD-3 → Delta above Bravo
    assert_equal %w[Alpha Charlie Delta Bravo], names
    assert_equal [1, 2, 3, 4], table.rows.map(&:position)
    assert_equal 4, table.rows.first.points
    assert_equal 3, table.rows.first.gd
  end

  test "counts only PostEvent matches and lists MidEvent as in_progress" do
    a, b = team("Echo"), team("Foxtrot")
    live = Match.create!(home_team: a, away_team: b, stage: "Group Stage",
                         status: "MidEvent", group_name: "Group Y",
                         match_id: "gt-live", home_score: 1, away_score: 0,
                         start_time: Time.zone.local(2026, 6, 11, 18, 0, 0))

    table = GroupTable.new("Group Y", [live])
    assert_equal [0, 0], table.rows.map(&:points)
    assert_equal [live], table.in_progress
  end

  test "flags teams level on points/GD/GF as tied" do
    a, b = team("Golf"), team("Hotel")
    Match.create!(home_team: a, away_team: b, stage: "Group Stage", status: "PostEvent",
                  group_name: "Group X", match_id: "gt-tie", home_score: 1, away_score: 1,
                  start_time: Time.zone.local(2026, 6, 11, 18, 0, 0))
    table = GroupTable.new("Group X", Match.where(group_name: "Group X").to_a)
    assert table.rows.all?(&:tied)
  end

  test ".all builds one table per distinct group_name" do
    a, b = team("India"), team("Juliet")
    played("Group W", a, b, 1, 0)
    groups = GroupTable.all.map(&:group_name)
    assert_includes groups, "Group W"
  end
end
