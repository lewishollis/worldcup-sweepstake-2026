class TournamentContextService
  def leaderboard
    groups = Group.includes(:friend, teams: [:home_matches, :away_matches]).all
    ranked = groups
      .map { |g| { friend: g.friend&.name || "No owner", score: g.total_points.to_f, teams: g.teams.map(&:name) } }
      .sort_by { |entry| -entry[:score] }
    ranked.each_with_index { |entry, i| entry[:rank] = i + 1 }
    ranked
  end

  def leaderboard_text
    status = tournament_status
    lb     = leaderboard
    lines  = ["TOURNAMENT STATUS: #{status.to_s.upcase.tr('_', ' ')}"]
    if status == :complete && (c = champion)
      lines << "CHAMPION: #{c[:team]}#{c[:owner] ? " (owned by #{c[:owner]})" : ''}"
    end
    lines << ""
    lb.each do |e|
      team_str = e[:teams].any? ? " [#{e[:teams].join(', ')}]" : ""
      lines << "#{e[:rank]}. #{e[:friend]}: #{e[:score].to_i} points#{team_str}"
    end
    lines.join("\n")
  end

  def tournament_status
    return :complete      if Match.exists?(stage: "Final", status: "PostEvent")
    return :knockout_stage if Match.where(stage: Team::KNOCKOUT_STAGES).exists?
    return :group_stage    if Match.exists?(stage: "Group Stage")
    :not_started
  end

  def champion
    final = Match.includes(:home_team, :away_team).find_by(stage: "Final", status: "PostEvent")
    return nil unless final
    return nil unless final.winner.in?(%w[home away])
    winning_team = final.winner == "home" ? final.home_team : final.away_team
    owner_group = Group.includes(:friend).joins(:teams).find_by(teams: { id: winning_team.id })
    { team: winning_team.name, owner: owner_group&.friend&.name }
  end

  # Returns up to `limit` recent NewsItems. Returns [] when NewsItem table doesn't exist yet.
  def news_items(limit: 5)
    return [] unless defined?(NewsItem) && NewsItem.table_exists?
    NewsItem.order(published_at: :desc).limit(limit).map do |item|
      { title: item.title, summary: item.summary, published_at: item.published_at }
    end
  rescue => e
    Rails.logger.warn("TournamentContextService#news_items failed: #{e.message}")
    []
  end

  # Returns top `limit` upcoming PreEvent matches ordered by start_time
  def upcoming_matches(limit: 10)
    Match.includes(:home_team, :away_team)
         .where(status: "PreEvent")
         .where("start_time > ?", Time.current)
         .order(:start_time)
         .limit(limit)
  end

  # Returns the 2-3 upcoming matches with the largest possible rank change for any friend
  def pivotal_matches(count: 3)
    upcoming = upcoming_matches(limit: 10)
    scored = upcoming.map do |match|
      scenarios = ScenarioEngine.new(match).call
      max_rank_change = scenarios.values.flat_map { |s| s[:rank_changes] }.map { |rc| (rc[:old_rank] - rc[:new_rank]).abs }.max || 0
      { match: match, max_rank_change: max_rank_change }
    end
    scored.sort_by { |s| -s[:max_rank_change] }.first(count).map { |s| s[:match] }
  end
end
