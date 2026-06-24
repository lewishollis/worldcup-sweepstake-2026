require "set"

# Single source of truth for whether a team has mathematically CLINCHED a top-2
# group finish — a guaranteed knockout place — independent of whether the BBC
# feed has published their knockout fixture yet.
#
# A team can be "Through" (top 2 in every remaining completion of the group)
# well before the feed schedules their Last-32 game, so keying "advanced" off the
# fixture alone leaves a visible delay. This lets Team#progressed? and the
# qualifying point land the moment qualification is certain.
#
# The clinched set is memoized at the class level and invalidated by
# GameStateSnapshot.data_version (a hash of every group-stage result), so it
# recomputes automatically when a group result changes and never goes stale.
class KnockoutQualification
  class << self
    def clinched?(team)
      clinched_team_ids.include?(team.id)
    end

    def clinched_team_ids
      version = GameStateSnapshot.data_version
      if @version != version
        @clinched_team_ids = compute_clinched_team_ids
        @version           = version
      end
      @clinched_team_ids
    end

    # Test/maintenance hook: drop the memoized set.
    def reset!
      @version = nil
      @clinched_team_ids = nil
    end

    private

    # A clinch is only mathematically valid if we hold the WHOLE group — the
    # oracle reasons about the remaining fixtures it can see, so a group missing
    # fixtures (incomplete feed, stale test data, a mis-parsed group_name) could
    # otherwise be read as "settled" and clinch a team that hasn't qualified.
    # We therefore only trust groups that are a complete 4-team round-robin.
    GROUP_SIZE        = 4
    EXPECTED_FIXTURES = GROUP_SIZE * (GROUP_SIZE - 1) / 2 # 6

    def compute_clinched_team_ids
      GroupTable.all.each_with_object(Set.new) do |table, ids|
        next unless complete_round_robin?(table)

        qualification = GroupQualification.new(table)
        table.teams.each { |team| ids << team.id if qualification.flag(team) == :clinched_top2 }
      end
    end

    # True only when the group holds exactly the 4 teams and all 6 distinct
    # pairings, each present once — anything else is incomplete or malformed and
    # is not safe to reason about.
    def complete_round_robin?(table)
      return false unless table.teams.size == GROUP_SIZE

      expected = table.teams.map(&:id).combination(2).map(&:sort).to_set
      actual   = table.matches.map { |m| [m.home_team_id, m.away_team_id].sort }
      actual.size == EXPECTED_FIXTURES && actual.to_set == expected
    end
  end
end
