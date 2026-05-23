# lib/tournament_simulation.rb
module TournamentSimulation
  # Returns teams sorted by group stage standings: points (3/1/0), then goal
  # difference, then goals scored. Takes AR Match objects from a single group.
  def self.calculate_standings(teams, matches)
    stats = teams.each_with_object({}) do |t, h|
      h[t.id] = { pts: 0, gd: 0, gf: 0 }
    end

    matches.each do |m|
      if m.home_score > m.away_score
        stats[m.home_team_id][:pts] += 3
      elsif m.home_score < m.away_score
        stats[m.away_team_id][:pts] += 3
      else
        stats[m.home_team_id][:pts] += 1
        stats[m.away_team_id][:pts] += 1
      end
      stats[m.home_team_id][:gd] += m.home_score - m.away_score
      stats[m.away_team_id][:gd] += m.away_score - m.home_score
      stats[m.home_team_id][:gf] += m.home_score
      stats[m.away_team_id][:gf] += m.away_score
    end

    teams.sort_by { |t| [-stats[t.id][:pts], -stats[t.id][:gd], -stats[t.id][:gf]] }
  end

  # Returns { pts:, gd:, gf: } for a single team across a list of matches.
  # Used to rank runners-up across groups.
  def self.standing_stats(team, matches)
    stats = { pts: 0, gd: 0, gf: 0 }
    matches.each do |m|
      next unless [m.home_team_id, m.away_team_id].include?(team.id)
      if m.home_team_id == team.id
        stats[:pts] += m.home_score > m.away_score ? 3 : (m.home_score == m.away_score ? 1 : 0)
        stats[:gd]  += m.home_score - m.away_score
        stats[:gf]  += m.home_score
      else
        stats[:pts] += m.away_score > m.home_score ? 3 : (m.home_score == m.away_score ? 1 : 0)
        stats[:gd]  += m.away_score - m.home_score
        stats[:gf]  += m.away_score
      end
    end
    stats
  end
end
