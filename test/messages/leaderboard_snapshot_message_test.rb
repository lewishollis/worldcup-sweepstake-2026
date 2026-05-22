require "test_helper"

class LeaderboardSnapshotMessageTest < ActiveSupport::TestCase
  setup do
    @alice = Friend.create!(name: "Alice")
    @bob = Friend.create!(name: "Bob")
    @charlie = Friend.create!(name: "Charlie")

    @g_alice = Group.create!(friend: @alice, name: "Alice's Group", multiplier: 1.0)
    @g_bob = Group.create!(friend: @bob, name: "Bob's Group", multiplier: 1.0)
    @g_charlie = Group.create!(friend: @charlie, name: "Charlie's Group", multiplier: 1.0)

    t1 = Team.create!(name: "Brazil", points: 5)
    t2 = Team.create!(name: "France", points: 3)
    t3 = Team.create!(name: "England", points: 1)

    @g_alice.teams << t1   # 5 pts
    @g_bob.teams << t2     # 3 pts
    @g_charlie.teams << t3 # 1 pt

    # Recalculate scores
    [@g_alice, @g_bob, @g_charlie].each(&:calculate_score)
  end

  teardown do
    Team.delete_all
    Group.delete_all
    Friend.delete_all
  end

  test "includes all friend names" do
    result = LeaderboardSnapshotMessage.call
    assert_includes result, "Alice"
    assert_includes result, "Bob"
    assert_includes result, "Charlie"
  end

  test "ranks by points descending" do
    result = LeaderboardSnapshotMessage.call
    alice_pos = result.index("Alice")
    bob_pos = result.index("Bob")
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
