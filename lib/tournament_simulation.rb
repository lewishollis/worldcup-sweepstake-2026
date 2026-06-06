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

  # Saves a simulated match so that team progression_score is computed from
  # actual match results (via Team#progression_score / Team#progressed?).
  # No dead columns (home_points, away_points, points, progressed) are written.
  def self.assign_simulation_points(match)
    # No-op: scoring is now derived from match results via Team#progression_score.
    # This method is kept for API compatibility with simulate_knockout_match.
  end

  # Creates and persists a PostEvent knockout match. Randomly picks a winner
  # (no draws in knockout). Scores reflect the winner. Calls
  # assign_simulation_points to award team points. Returns the saved Match.
  def self.simulate_knockout_match(home_team, away_team, stage, idx, id_prefix)
    winner = %w[home away].sample

    if winner == "home"
      home_score = rand(1..3)
      away_score = rand(0..home_score - 1)
    else
      away_score = rand(1..3)
      home_score = rand(0..away_score - 1)
    end

    match = Match.new(
      home_team:  home_team,
      away_team:  away_team,
      home_score: home_score,
      away_score: away_score,
      winner:     winner,
      status:     "PostEvent",
      stage:      stage,
      start_time: Time.now,
      match_id:   "#{id_prefix}-#{idx}"
    )

    assign_simulation_points(match)
    match.save!
    match
  end
end
