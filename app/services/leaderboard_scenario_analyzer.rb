class LeaderboardScenarioAnalyzer
  def initialize(friend)
    @friend = friend
    @current_standings = calculate_current_standings
    @friend_position = @current_standings.index { |f| f[:friend] == @friend } + 1
  end

  # Find what results the friend needs to move up
  def analyze_path_to_top
    return nil if @friend_position == 1 # Already winning!

    upcoming_matches = Match.where(status: 'PreEvent')
                            .where('start_time > ?', Time.current)
                            .order(:start_time)
                            .limit(10)

    # Get friend's teams
    friend_team_ids = Team.where(friend_id: @friend.id).pluck(:id)

    scenarios = []

    # Analyze each upcoming match
    upcoming_matches.each do |match|
      # Check if friend's team is playing
      if friend_team_ids.include?(match.home_team_id)
        scenarios << analyze_match_scenario(match, :home_win, friend_team_ids)
      elsif friend_team_ids.include?(match.away_team_id)
        scenarios << analyze_match_scenario(match, :away_win, friend_team_ids)
      end

      # Check how other results affect the friend
      scenarios << analyze_other_results(match, friend_team_ids)
    end

    # Find the best scenario for the friend
    best_scenario = find_best_scenario(scenarios.compact)

    {
      current_position: @friend_position,
      current_points: @friend.total_points,
      leader_points: @current_standings.first[:points],
      points_behind: @current_standings.first[:points] - @friend.total_points,
      best_scenario: best_scenario,
      upcoming_matches: format_upcoming_matches(upcoming_matches, friend_team_ids)
    }
  end

  private

  def calculate_current_standings
    # Calculate points for all friends
    Friend.all.map do |friend|
      total_points = Team.where(friend_id: friend.id).sum do |team|
        calculate_team_points(team)
      end

      {
        friend: friend,
        name: friend.name,
        points: total_points
      }
    end.sort_by { |f| -f[:points] }
  end

  def calculate_team_points(team)
    # Points calculation logic (adjust based on your scoring system)
    team.matches.where(status: 'PostEvent').sum do |match|
      if match.home_team_id == team.id
        match.home_score > match.away_score ? 3 : (match.home_score == match.away_score ? 1 : 0)
      else
        match.away_score > match.home_score ? 3 : (match.away_score == match.home_score ? 1 : 0)
      end
    end
  end

  def analyze_match_scenario(match, outcome, friend_team_ids)
    # Calculate points if this outcome happens
    projected_standings = calculate_projected_standings(match, outcome)

    friend_new_position = projected_standings.index { |f| f[:friend] == @friend } + 1

    {
      match: match,
      outcome: outcome,
      position_change: @friend_position - friend_new_position,
      new_position: friend_new_position,
      description: describe_outcome(match, outcome)
    }
  end

  def analyze_other_results(match, friend_team_ids)
    # Check if other friends' teams are playing
    home_friend = match.home_team.friend
    away_friend = match.away_team.friend

    return nil if home_friend == @friend || away_friend == @friend

    # Find which outcome benefits the friend most
    home_win_standings = calculate_projected_standings(match, :home_win)
    away_win_standings = calculate_projected_standings(match, :away_win)

    friend_pos_if_home_wins = home_win_standings.index { |f| f[:friend] == @friend } + 1
    friend_pos_if_away_wins = away_win_standings.index { |f| f[:friend] == @friend } + 1

    if friend_pos_if_home_wins < @friend_position
      {
        match: match,
        outcome: :home_win,
        position_change: @friend_position - friend_pos_if_home_wins,
        new_position: friend_pos_if_home_wins,
        description: describe_outcome(match, :home_win),
        benefit_type: :indirect # Not your team, but helps you
      }
    elsif friend_pos_if_away_wins < @friend_position
      {
        match: match,
        outcome: :away_win,
        position_change: @friend_position - friend_pos_if_away_wins,
        new_position: friend_pos_if_away_wins,
        description: describe_outcome(match, :away_win),
        benefit_type: :indirect
      }
    end
  end

  def calculate_projected_standings(match, outcome)
    # Simulate the outcome and recalculate standings
    # This is a projection, doesn't save to DB
    points_change = case outcome
                    when :home_win then { home: 3, away: 0 }
                    when :away_win then { home: 0, away: 3 }
                    when :draw then { home: 1, away: 1 }
                    end

    # Calculate new standings with this result
    Friend.all.map do |friend|
      total_points = Team.where(friend_id: friend.id).sum do |team|
        base_points = calculate_team_points(team)

        # Add projected points if this is their team
        if match.home_team_id == team.id
          base_points + points_change[:home]
        elsif match.away_team_id == team.id
          base_points + points_change[:away]
        else
          base_points
        end
      end

      {
        friend: friend,
        name: friend.name,
        points: total_points
      }
    end.sort_by { |f| -f[:points] }
  end

  def find_best_scenario(scenarios)
    # Find the scenario that gives the biggest position improvement
    scenarios.select { |s| s[:position_change] > 0 }
             .max_by { |s| s[:position_change] }
  end

  def describe_outcome(match, outcome)
    case outcome
    when :home_win
      "#{match.home_team.name} beats #{match.away_team.name}"
    when :away_win
      "#{match.away_team.name} beats #{match.home_team.name}"
    when :draw
      "#{match.home_team.name} draws with #{match.away_team.name}"
    end
  end

  def format_upcoming_matches(matches, friend_team_ids)
    matches.map do |match|
      is_friend_team = friend_team_ids.include?(match.home_team_id) ||
                      friend_team_ids.include?(match.away_team_id)

      {
        match: match,
        is_friend_team: is_friend_team,
        home_team: match.home_team.name,
        away_team: match.away_team.name,
        date: match.start_time
      }
    end
  end
end
