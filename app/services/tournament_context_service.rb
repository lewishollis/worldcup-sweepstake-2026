class TournamentContextService
  def leaderboard
    groups = Group.includes(:teams, :friend).all
    ranked = groups
      .map { |g| { friend: g.friend&.name || "No owner", score: g.total_points.to_f, multiplier: g.multiplier.to_i } }
      .sort_by { |entry| -entry[:score] }
    ranked.each_with_index { |entry, i| entry[:rank] = i + 1 }
    ranked
  end

  def leaderboard_text
    leaderboard.map { |e| "#{e[:rank]}. #{e[:friend]}: #{e[:score].to_i} points (×#{e[:multiplier]})" }.join("\n")
  end

  # Returns up to `limit` recent NewsItems. Returns [] when NewsItem table doesn't exist yet (Phase 1 safety).
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
