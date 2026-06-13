# Computes mathematically-safe top-2 qualification flags for a GroupTable by
# enumerating every possible completion of the group's remaining matches.
# Evaluation is on POINTS ONLY: goal-difference outcomes are unbounded, so a
# points-tie at the top-2 boundary is treated as "not safe" (conservative).
#
#   :clinched_top2      - top 2 in EVERY completion, even under the worst tiebreak
#   :cannot_finish_top2 - top 2 in NO completion, even under the best tiebreak
#   :in_contention      - otherwise (nothing certain is asserted about top 2)
class GroupQualification
  OUTCOMES = %i[home_win draw away_win].freeze

  def initialize(group_table)
    @table = group_table
    @base  = base_points
  end

  def flag(team)
    classify(team.id, completions)
  end

  # For an upcoming group match, returns the per-team flag under each outcome:
  # { home_win: { home: {team:, flag:}, away: {team:, flag:} }, draw: {...}, away_win: {...} }
  def effects(match)
    OUTCOMES.each_with_object({}) do |outcome, result|
      comps = completions(fixed: { match.id => [match, outcome] })
      result[outcome] = {
        home: { team: match.home_team, flag: classify(match.home_team_id, comps) },
        away: { team: match.away_team, flag: classify(match.away_team_id, comps) }
      }
    end
  end

  private

  def remaining_matches
    @remaining_matches ||= @table.matches.reject { |m| m.status == "PostEvent" }
  end

  # team_id => points earned from completed (PostEvent) matches; all teams seeded to 0.
  def base_points
    points = {}
    @table.teams.each { |t| points[t.id] = 0 }
    @table.matches.each do |m|
      next unless m.status == "PostEvent" && m.home_score && m.away_score

      award(points, m.home_team_id, m.away_team_id, m.home_score <=> m.away_score)
    end
    points
  end

  # comparison: 1 home win, 0 draw, -1 away win
  def award(points, home_id, away_id, comparison)
    case comparison
    when 1  then points[home_id] += 3
    when 0  then points[home_id] += 1; points[away_id] += 1
    when -1 then points[away_id] += 3
    end
  end

  def apply_outcome(points, match, outcome)
    case outcome
    when :home_win then award(points, match.home_team_id, match.away_team_id, 1)
    when :draw     then award(points, match.home_team_id, match.away_team_id, 0)
    when :away_win then award(points, match.home_team_id, match.away_team_id, -1)
    end
    points
  end

  # Returns an array of final points-maps, one per completion. `fixed` pins
  # specific matches to an outcome: { match_id => [match, outcome] }.
  def completions(fixed: {})
    start = @base.dup
    fixed.each_value { |match, outcome| apply_outcome(start, match, outcome) }
    open = remaining_matches.reject { |m| fixed.key?(m.id) }
    enumerate(open, start)
  end

  def enumerate(matches, points)
    return [points] if matches.empty?

    head, *tail = matches
    OUTCOMES.flat_map { |outcome| enumerate(tail, apply_outcome(points.dup, head, outcome)) }
  end

  def classify(team_id, comps)
    return :clinched_top2      if comps.all? { |points| safe_top2?(team_id, points) }
    return :cannot_finish_top2 if comps.all? { |points| safe_out?(team_id, points) }

    :in_contention
  end

  # Safe top 2: even if every points-tie breaks against this team, no more than
  # one other team finishes at or above it.
  def safe_top2?(team_id, points)
    mine = points[team_id]
    at_or_above = points.count { |id, p| id != team_id && p >= mine }
    at_or_above <= 1
  end

  # Safe out: at least two other teams strictly out-point this team.
  def safe_out?(team_id, points)
    mine = points[team_id]
    points.count { |id, p| id != team_id && p > mine } >= 2
  end
end
