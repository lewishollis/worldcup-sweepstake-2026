# Per-friend sweepstake insight, grounded in the app's real scoring
# (Group#total_points, which sums Team#progression_score) and the shared
# GameStateSnapshot's group situations. Replaces the old
# LeaderboardScenarioAnalyzer-based version, which used a league-style 3/1/0
# model that contradicted the actual leaderboard.
class AiLeaderboardInsightsService
  PERSONA_VERSION = "gary-lineker-v2".freeze

  def initialize(friend)
    @friend   = friend
    @snapshot = GameStateSnapshot.new
  end

  # Returns { commentary: String, analysis: Hash }.
  def generate_personalized_insight
    analysis = build_analysis
    { commentary: commentary_for(analysis), analysis: analysis }
  rescue => e
    Rails.logger.error("AiLeaderboardInsightsService failed: #{e.message}")
    { commentary: "The race is on — keep an eye on your teams.", analysis: {} }
  end

  private

  def commentary_for(analysis)
    return winner_message if analysis[:position] == 1

    version = cache_version
    if AiInsightCache.table_exists?
      cached = AiInsightCache.fetch(key: cache_key, version: version)
      return cached if cached
    end

    generated = GroqClient.call(system_prompt: build_system_prompt,
                                user_message: build_user_message(analysis),
                                max_tokens: 200)
    if generated
      AiInsightCache.store(key: cache_key, version: version, content: generated) if AiInsightCache.table_exists?
      generated
    else
      fallback(analysis) # deliberately not cached so a real insight can replace it
    end
  end

  def build_analysis
    groups = Group.includes(:friend, teams: [:home_matches, :away_matches]).to_a
                  .sort_by { |g| -g.total_points }
    my_group = groups.find { |g| g.friend_id == @friend.id }
    return empty_analysis unless my_group

    leader_points = groups.first.total_points.to_f
    points        = my_group.total_points.to_f
    {
      position:       groups.index(my_group) + 1,
      points:         points,
      leader_points:  leader_points,
      points_behind:  (leader_points - points),
      team_summaries: my_group.teams.filter_map { |t| @snapshot.team_group_summary(t) }
    }
  end

  def empty_analysis
    { position: nil, points: 0.0, leader_points: 0.0, points_behind: 0.0, team_summaries: [] }
  end

  def build_system_prompt
    [
      "You are Gary Lineker, the former England striker turned BBC Match of the Day presenter, giving #{@friend.name} a short, personalised sweepstake update.",
      "Voice: warm, articulate, dry gentle wit. Clean enough for a family group chat. 2-3 sentences, no lists or markdown.",
      "",
      "SCORING: points are only won in the KNOCKOUT stages (+1 for reaching the main knockout bracket, then +1 per knockout win). Group-stage matches award no points directly, but they decide who qualifies — so a group win is never meaningless.",
      "ACCURACY: use only the positions, points, and group situations provided. Never invent numbers or results.",
      "Never write your own name or sign the update — no by-line, no presenter name (not 'Gary Lineker', not 'John Botson'). Just write the update itself."
    ].join("\n")
  end

  def build_user_message(analysis)
    lines = ["#{@friend.name}'s situation:"]
    lines << "- Currently #{ordinal(analysis[:position])} on #{fmt(analysis[:points])} points; the leader has #{fmt(analysis[:leader_points])} (#{fmt(analysis[:points_behind])} behind)."
    if analysis[:team_summaries].any?
      lines << "- Their teams in the group stage:"
      analysis[:team_summaries].each { |s| lines << "  • #{s}" }
    end
    lines << ""
    lines << "Write #{@friend.name}'s update now (2-3 sentences), focusing on what their teams need to reach or progress in the knockouts."
    lines.join("\n")
  end

  def fallback(analysis)
    return "You're right in the mix — keep your teams winning." if analysis[:position].nil?

    "You're #{ordinal(analysis[:position])} on #{fmt(analysis[:points])} points, #{fmt(analysis[:points_behind])} behind the leader. Your teams need to keep qualifying and winning in the knockouts."
  end

  def winner_message
    "Top of the pile! You're leading the sweepstake — now keep your teams winning to stay there."
  end

  def cache_key
    "friend_insight_#{@friend.id}"
  end

  def cache_version
    totals = Group.includes(teams: [:home_matches, :away_matches]).order(:id)
                  .map { |g| "#{g.id}:#{g.total_points}" }.join("|")
    Digest::SHA256.hexdigest("#{PERSONA_VERSION}|#{@friend.id}|#{totals}|#{GameStateSnapshot.data_version}")[0, 16]
  end

  def ordinal(n)
    return "—" if n.nil?

    %w[0th 1st 2nd 3rd 4th 5th 6th 7th 8th 9th 10th 11th 12th].fetch(n, "#{n}th")
  end

  def fmt(value)
    (value % 1).zero? ? value.to_i : value
  end
end
