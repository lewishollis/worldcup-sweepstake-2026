class MatchResultMessage
  def self.call(match)
    new(match).call
  end

  def initialize(match)
    @match = match
  end

  def call
    m = @match
    home_friend = m.home_team.groups.first&.friend&.name || "No owner"
    away_friend = m.away_team.groups.first&.friend&.name || "No owner"

    [
      "⚽ *Full Time!*",
      "#{m.home_team.name} #{m.home_score} - #{m.away_score} #{m.away_team.name}",
      "",
      "#{m.home_team.name} → #{home_friend}#{points_label(home_points_for(m))}",
      "#{m.away_team.name} → #{away_friend}#{points_label(away_points_for(m))}"
    ].join("\n")
  end

  private

  KNOCKOUT_STAGES = ["Last 16", "Quarter-finals", "Semi-finals", "3rd Place Final", "Final"].freeze

  def home_points_for(match)
    return 0 unless KNOCKOUT_STAGES.include?(match.stage)

    case match.stage
    when "Final"
      match.winner == "home" ? 2 : 1
    else
      match.winner == "home" ? 1 : 0
    end
  end

  def away_points_for(match)
    return 0 unless KNOCKOUT_STAGES.include?(match.stage)

    case match.stage
    when "Final"
      match.winner == "away" ? 2 : 1
    else
      match.winner == "away" ? 1 : 0
    end
  end

  def points_label(pts)
    return "" if pts.to_i.zero?

    " (+#{pts.to_i} pt#{pts.to_i > 1 ? 's' : ''})"
  end
end
