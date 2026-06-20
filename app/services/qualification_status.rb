# Maps one team to a single user-facing qualification status by combining the
# tested points-only oracle (GroupQualification) with the team's live table
# position (GroupTable). "Likely" is derived here, at the presentation layer,
# so the oracle stays purely mathematical: a team that is top-2 only on goal
# difference reads as :likely ("in a qualifying spot, not yet safe") rather
# than the oracle's conservative :in_contention.
class QualificationStatus
  LABELS = {
    through:    "Through",
    likely:     "Likely",
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
    case @qualification.flag(@team)
    when :clinched_top2      then :through
    when :cannot_finish_top2 then :out
    else likely_top2? ? :likely : :contention
    end
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
end
