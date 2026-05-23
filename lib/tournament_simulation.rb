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

  # Assigns sweepstake points to both teams for a simulated match. Modifies
  # match.home_points / away_points in-place and persists updated team points.
  # Also grants +1 progression point to any team appearing in a knockout match
  # for the first time (mirrors MatchesController#assign_points logic).
  def self.assign_simulation_points(match)
    stage = match.stage
    knockout_stages = ["Last 16", "Quarter-finals", "Semi-finals", "Final", "3rd Place Final"]

    if knockout_stages.include?(stage)
      home_team = match.home_team
      unless home_team.progressed?
        home_team.update!(progressed: true, points: home_team.points + 1)
      end

      away_team = match.away_team
      unless away_team.progressed?
        away_team.update!(progressed: true, points: away_team.points + 1)
      end
    end

    case stage
    when "Group Stage"
      match.home_points = 0
      match.away_points = 0
    when "Last 16", "Quarter-finals", "Semi-finals", "3rd Place Final"
      match.home_points = match.winner == "home" ? 1 : 0
      match.away_points = match.winner == "away" ? 1 : 0
    when "Final"
      match.home_points = match.winner == "home" ? 2 : 1
      match.away_points = match.winner == "away" ? 2 : 1
    else
      match.home_points = 0
      match.away_points = 0
    end

    match.home_team.reload.update!(points: match.home_team.points + match.home_points) if match.home_points > 0
    match.away_team.reload.update!(points: match.away_team.points + match.away_points) if match.away_points > 0
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
      match_id:   "#{id_prefix}-#{idx}",
      result:     winner == "home" ? "W" : "L"
    )

    assign_simulation_points(match)
    match.save!
    match
  end
end
