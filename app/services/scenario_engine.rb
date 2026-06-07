class ScenarioEngine
  def initialize(match)
    @match = match
    @all_groups = Group.includes(:teams, :friend).all
    # Preload whether each team has already played a PostEvent knockout match (earned qualify bonus)
    @home_has_qualified = Match.where(status: "PostEvent", stage: Team::MAIN_KNOCKOUT_STAGES)
                               .where("home_team_id = ? OR away_team_id = ?", match.home_team_id, match.home_team_id)
                               .where.not(id: match.id)
                               .exists?
    @away_has_qualified = Match.where(status: "PostEvent", stage: Team::MAIN_KNOCKOUT_STAGES)
                               .where("home_team_id = ? OR away_team_id = ?", match.away_team_id, match.away_team_id)
                               .where.not(id: match.id)
                               .exists?
  end

  def call
    outcomes.each_with_object({}) do |outcome, result|
      result[outcome] = compute_scenario(outcome)
    end
  end

  private

  def outcomes
    @match.stage == "Group Stage" ? %i[home_win draw away_win] : %i[home_win away_win]
  end

  def compute_scenario(outcome)
    team_pts   = team_points_for(outcome)
    delta_map  = build_delta_map(team_pts)
    friend_scores = current_friend_scores
    projected     = projected_friend_scores(friend_scores, delta_map)

    {
      team_points:   team_pts,
      friend_deltas: compute_friend_deltas(friend_scores, projected),
      rank_changes:  compute_rank_changes(friend_scores, projected),
      new_leader:    projected.max_by { |fs| fs[:projected_score] }&.dig(:friend_name)
    }
  end

  # Returns array of { team_id:, team_name:, points_awarded:, reason: }
  def team_points_for(outcome)
    stage = @match.stage
    return [] if stage == "Group Stage"

    points = []

    # Award +1 qualify bonus to any team appearing in their first PostEvent knockout match
    [
      { id: @match.home_team_id, name: @match.home_team.name, qualified: @home_has_qualified },
      { id: @match.away_team_id, name: @match.away_team.name, qualified: @away_has_qualified }
    ].each do |t|
      next if t[:qualified]
      points << { team_id: t[:id], team_name: t[:name], points_awarded: 1, reason: "Qualify from group stage" }
    end

    case stage
    when "Last 32", "Last 16", "Quarter-finals", "Semi-finals"
      case outcome
      when :home_win
        points << { team_id: @match.home_team_id, team_name: @match.home_team.name,
                    points_awarded: 1, reason: "#{stage} win" }
      when :away_win
        points << { team_id: @match.away_team_id, team_name: @match.away_team.name,
                    points_awarded: 1, reason: "#{stage} win" }
      end
    when "3rd Place Final"
      case outcome
      when :home_win
        points << { team_id: @match.home_team_id, team_name: @match.home_team.name,
                    points_awarded: 0.5, reason: "3rd Place Final win" }
      when :away_win
        points << { team_id: @match.away_team_id, team_name: @match.away_team.name,
                    points_awarded: 0.5, reason: "3rd Place Final win" }
      end
    when "Final"
      case outcome
      when :home_win
        points << { team_id: @match.home_team_id, team_name: @match.home_team.name,
                    points_awarded: 1, reason: "Final win" }
      when :away_win
        points << { team_id: @match.away_team_id, team_name: @match.away_team.name,
                    points_awarded: 1, reason: "Final win" }
      end
    end

    points
  end

  # { team_id => additional_points } lookup
  def build_delta_map(team_pts)
    team_pts.each_with_object({}) do |tp, h|
      h[tp[:team_id]] = (h[tp[:team_id]] || 0) + tp[:points_awarded]
    end
  end

  # Current friend scores: [{ friend_name:, group_id:, team_ids:, current_score: }]
  def current_friend_scores
    @all_groups.map do |group|
      {
        friend_name:   group.friend&.name || "No owner",
        group_id:      group.id,
        team_ids:      group.teams.map(&:id),
        current_score: group.total_points.to_f
      }
    end
  end

  # Returns friend_scores with :projected_score added
  def projected_friend_scores(friend_scores, delta_map)
    friend_scores.map do |fs|
      additional = fs[:team_ids].sum { |tid| (delta_map[tid] || 0).to_f }
      fs.merge(projected_score: fs[:current_score] + additional)
    end
  end

  def compute_friend_deltas(friend_scores, projected)
    projected.filter_map do |ps|
      delta = ps[:projected_score] - ps[:current_score]
      next if delta.zero?
      { friend: ps[:friend_name], delta: delta, new_total: ps[:projected_score] }
    end
  end

  def compute_rank_changes(friend_scores, projected)
    current_ranked  = friend_scores.sort_by { |fs| -fs[:current_score] }
    projected_ranked = projected.sort_by { |fs| -fs[:projected_score] }

    current_ranked.filter_map.with_index do |fs, i|
      old_rank = i + 1
      new_rank = projected_ranked.index { |pr| pr[:friend_name] == fs[:friend_name] }.to_i + 1
      next if old_rank == new_rank
      { friend: fs[:friend_name], old_rank: old_rank, new_rank: new_rank }
    end
  end
end
