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

    def compute_clinched_team_ids
      GroupTable.all.each_with_object(Set.new) do |table, ids|
        qualification = GroupQualification.new(table)
        table.teams.each { |team| ids << team.id if qualification.flag(team) == :clinched_top2 }
      end
    end
  end
end
