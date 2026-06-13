# Computes one tournament group's standings table from its group-stage matches.
# Only PostEvent matches count toward the table; MidEvent matches are surfaced
# separately so a half-played game is never reported as final. Sort order is
# points -> goal difference -> goals for; teams level on all three are flagged
# `tied` rather than given an invented order (deeper FIFA tiebreakers are not
# derivable from our data).
class GroupTable
  Row = Struct.new(:team, :played, :won, :drawn, :lost, :gf, :ga, :gd, :points,
                   :position, :tied, keyword_init: true)

  # Returns one GroupTable per distinct group_name on group-stage matches.
  def self.all
    Match.where(stage: "Group Stage")
         .where.not(group_name: [nil, ""])
         .includes(:home_team, :away_team)
         .to_a
         .group_by(&:group_name)
         .sort
         .map { |name, matches| new(name, matches) }
  end

  attr_reader :group_name, :matches

  def initialize(group_name, matches)
    @group_name = group_name
    @matches    = matches
  end

  def teams
    @teams ||= @matches.flat_map { |m| [m.home_team, m.away_team] }.uniq
  end

  def in_progress
    @matches.select { |m| m.status == "MidEvent" }
  end

  def rows
    @rows ||= build_rows
  end

  private

  def build_rows
    stats = {}
    teams.each { |t| stats[t.id] = { played: 0, won: 0, drawn: 0, lost: 0, gf: 0, ga: 0 } }

    completed.each do |m|
      apply(stats[m.home_team_id], m.home_score, m.away_score)
      apply(stats[m.away_team_id], m.away_score, m.home_score)
    end

    rows = teams.map do |team|
      s = stats[team.id]
      Row.new(team: team, played: s[:played], won: s[:won], drawn: s[:drawn], lost: s[:lost],
              gf: s[:gf], ga: s[:ga], gd: s[:gf] - s[:ga], points: s[:won] * 3 + s[:drawn],
              position: nil, tied: false)
    end

    sorted = rows.sort_by { |r| [-r.points, -r.gd, -r.gf] }
    sorted.each_with_index do |row, i|
      row.position = i + 1
      neighbours = [sorted[i - 1], (sorted[i + 1] if i + 1 < sorted.length)]
      neighbours[0] = nil if i.zero?
      row.tied = neighbours.compact.any? { |o| sort_key(o) == sort_key(row) }
    end
    sorted
  end

  def completed
    @matches.select { |m| m.status == "PostEvent" && m.home_score && m.away_score }
  end

  def sort_key(row)
    [row.points, row.gd, row.gf]
  end

  def apply(stat, for_goals, against_goals)
    stat[:played] += 1
    stat[:gf] += for_goals
    stat[:ga] += against_goals
    if for_goals > against_goals
      stat[:won] += 1
    elsif for_goals == against_goals
      stat[:drawn] += 1
    else
      stat[:lost] += 1
    end
  end
end
