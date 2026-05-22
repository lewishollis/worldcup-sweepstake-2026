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
      "#{m.home_team.name} → #{home_friend}#{points_label(m.home_points)}",
      "#{m.away_team.name} → #{away_friend}#{points_label(m.away_points)}"
    ].join("\n")
  end

  private

  def points_label(pts)
    return "" if pts.to_i.zero?

    " (+#{pts} pt#{pts > 1 ? 's' : ''})"
  end
end
