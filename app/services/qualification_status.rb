# Maps one team to a single user-facing qualification status by combining the
# tested points-only oracle (GroupQualification) with the team's live table
# position (GroupTable). "Likely" is derived here, at the presentation layer,
# so the oracle stays purely mathematical: a team that is top-2 only on goal
# difference reads as :likely ("in a qualifying spot, not yet safe") rather
# than the oracle's conservative :in_contention.
#
# "Out" means eliminated from EVERY route — both the top 2 and the best-third
# path (8 of the 12 third-placed teams advance). A team that can no longer
# finish top 2 but can still finish 3rd is :third_hope, not :out.
class QualificationStatus
  LABELS = {
    through:    "Through",
    likely:     "Likely",
    third_hope: "3rd-place hope",
    out:        "Out",
    contention: "In the mix"
  }.freeze

  def self.for(team, table:, qualification:)
    new(team, table, qualification).key
  end

  def self.label(key)
    LABELS.fetch(key)
  end

  def initialize(team, table, qualification)
    @team          = team
    @table         = table
    @qualification = qualification
  end

  # The top two of a group qualify.
  QUALIFYING_SLOTS = 2

  def key
    # A confirmed knockout berth — a clinched top-2 finish OR an actual knockout
    # fixture already drawn (the best-third path the group oracle can't confirm) —
    # reads as :through. This keeps the badge in step with the "Advanced" pill,
    # which is driven by the same Team#progressed? signal.
    return :through if @team.progressed?
    return :out     if @qualification.cannot_reach_knockouts?(@team)

    # Top 2 is mathematically gone. If group games remain, the team may still
    # take the best-third-placed route. Once all games are done, that selection
    # has already happened — if they didn't progress, they're out.
    if @qualification.flag(@team) == :cannot_finish_top2
      return group_games_remaining? ? :third_hope : :out
    end

    likely_top2? ? :likely : :contention
  end

  private

  # A top-2 slot earned only on goal difference is fragile, so "Likely" demands
  # daylight on POINTS: the team must out-point whoever sits in the first
  # non-qualifying slot. Teams level on points — even if nosed ahead on GD or
  # goals scored — are still :contention, not :likely.
  def likely_top2?
    rows = @table.rows
    row  = rows.find { |r| r.team.id == @team.id }
    return false unless row && row.position <= QUALIFYING_SLOTS

    first_below_line = rows[QUALIFYING_SLOTS] # 0-based index == position (slots + 1)
    first_below_line.nil? || row.points > first_below_line.points
  end

  def group_games_remaining?
    @table.matches.any? { |m| m.status != "PostEvent" }
  end
end
