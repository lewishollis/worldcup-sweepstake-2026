require "test_helper"

class LeaderboardSnapshotMessageTest < ActiveSupport::TestCase
  setup do
    @alice   = Friend.create!(name: "Alice")
    @bob     = Friend.create!(name: "Bob")
    @charlie = Friend.create!(name: "Charlie")

    @g_alice   = Group.create!(friend: @alice,   name: "Alice's Group")
    @g_bob     = Group.create!(friend: @bob,     name: "Bob's Group")
    @g_charlie = Group.create!(friend: @charlie, name: "Charlie's Group")

    t_alice   = Team.create!(name: "Brazil")
    t_bob     = Team.create!(name: "France")
    t_charlie = Team.create!(name: "England")
    opp       = Team.create!(name: "Germany")

    @g_alice.teams   << t_alice
    @g_bob.teams     << t_bob
    @g_charlie.teams << t_charlie

    # Alice's team: qualify + win R32 + win R16 + win QF + win SF = 5.0 pts
    Match.create!(home_team: t_alice, away_team: opp, stage: "Last 32",      status: "PostEvent", winner: "home", match_id: "a-r32", start_time: 5.days.ago)
    Match.create!(home_team: t_alice, away_team: opp, stage: "Last 16",      status: "PostEvent", winner: "home", match_id: "a-r16", start_time: 4.days.ago)
    Match.create!(home_team: t_alice, away_team: opp, stage: "Quarter-finals", status: "PostEvent", winner: "home", match_id: "a-qf",  start_time: 3.days.ago)
    Match.create!(home_team: t_alice, away_team: opp, stage: "Semi-finals",  status: "PostEvent", winner: "home", match_id: "a-sf",  start_time: 2.days.ago)

    # Bob's team: qualify + win R32 + win R16 = 3.0 pts
    Match.create!(home_team: t_bob, away_team: opp, stage: "Last 32", status: "PostEvent", winner: "home", match_id: "b-r32", start_time: 3.days.ago)
    Match.create!(home_team: t_bob, away_team: opp, stage: "Last 16", status: "PostEvent", winner: "home", match_id: "b-r16", start_time: 2.days.ago)

    # Charlie's team: qualify (lost in Last 32) = 1.0 pt
    Match.create!(home_team: t_charlie, away_team: opp, stage: "Last 32", status: "PostEvent", winner: "away", match_id: "c-r32", start_time: 2.days.ago)
  end

  test "includes all friend names" do
    result = LeaderboardSnapshotMessage.call
    assert_includes result, "Alice"
    assert_includes result, "Bob"
    assert_includes result, "Charlie"
  end

  test "ranks by points descending" do
    result = LeaderboardSnapshotMessage.call
    alice_pos   = result.index("Alice")
    bob_pos     = result.index("Bob")
    charlie_pos = result.index("Charlie")

    assert alice_pos < bob_pos
    assert bob_pos < charlie_pos
  end

  test "includes points totals" do
    result = LeaderboardSnapshotMessage.call
    assert_includes result, "5"
    assert_includes result, "3"
    assert_includes result, "1"
  end
end
