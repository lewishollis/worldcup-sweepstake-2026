class MorningFixturesMessage
  def self.call(date = Date.today)
    new(date).call
  end

  def initialize(date)
    @date = date
  end

  def call
    matches = Match.where(status: "PreEvent")
                   .where("DATE(start_time) = ?", @date)
                   .includes(home_team: :groups, away_team: :groups)
                   .order(:start_time)

    return nil if matches.empty?

    lines = ["⚽ *World Cup Today — #{@date.strftime('%A %-d %B')}*\n"]

    matches.each do |m|
      home_friend = m.home_team.groups.first&.friend&.name || "No owner"
      away_friend = m.away_team.groups.first&.friend&.name || "No owner"
      time = m.start_time.in_time_zone("London").strftime("%-I:%M%p")
      lines << "#{time} | #{m.home_team.name} (#{home_friend}) vs #{m.away_team.name} (#{away_friend})"
    end

    lines.join("\n")
  end
end
