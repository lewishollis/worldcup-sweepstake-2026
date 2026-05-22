class LeaderboardSnapshotMessage
  MEDALS = ["🥇", "🥈", "🥉"].freeze

  def self.call
    new.call
  end

  def call
    groups = Group.includes(:teams, :friend).sort_by { |g| -g.total_points }

    lines = ["📊 *Leaderboard*\n"]
    groups.each_with_index do |group, i|
      position = MEDALS[i] || "#{i + 1}."
      name = group.friend&.name || group.name || "Unknown"
      lines << "#{position} #{name} — #{group.total_points.to_i} pts"
    end

    lines.join("\n")
  end
end
