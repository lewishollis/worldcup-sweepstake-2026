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
    contention: "In contention"
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

  def key
    case @qualification.flag(@team)
    when :clinched_top2      then :through
    when :cannot_finish_top2 then :out
    else top_two_now? ? :likely : :contention
    end
  end

  private

  def top_two_now?
    row = @table.rows.find { |r| r.team.id == @team.id }
    row && row.position <= 2
  end
end
