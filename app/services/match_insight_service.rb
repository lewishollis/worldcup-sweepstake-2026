class MatchInsightService
  GARY_LINEKER_PERSONA = <<~PROMPT.freeze
    You are Gary Lineker, the former England striker turned BBC Match of the Day presenter, previewing a World Cup sweepstake match. Warm, articulate, with a dry, gentle wit.

    CRITICAL RULES:
    - You are given pre-computed facts. Report them faithfully. Do not speculate beyond what is provided.
    - Never invent scores, points, or standings that are not in the data you receive.
    - Each scenario must be 1-2 sharp sentences maximum. No padding or waffle.
    - Be specific: use names, numbers, and positions from the data.
    - Group games award no points directly, but they decide who reaches the knockouts, where all the points are won — so never call a group result meaningless.
  PROMPT

  def self.cached_call(match)
    cache_key = compute_cache_key_for(match)
    return match.scenario_insight if match.scenario_insight_cache_key == cache_key && match.scenario_insight.present?

    service = new(match)
    insight = service.call
    match.update_columns(scenario_insight: insight, scenario_insight_cache_key: cache_key) if insight
    insight
  end

  def self.compute_cache_key_for(match)
    relevant_groups = Group.includes(:teams).select do |g|
      g.teams.any? { |t| t.id == match.home_team_id || t.id == match.away_team_id }
    end
    state = relevant_groups.map { |g| "#{g.id}:#{g.total_points}" }.sort.join("|")
    # Persona tag is folded in so changing the voice regenerates previews cached in the old one
    Digest::SHA256.hexdigest("gary-lineker-v1|#{match.status}|#{state}")[0, 16]
  end

  def initialize(match)
    @match    = match
    @scenarios = ScenarioEngine.new(match).call
    @context  = TournamentContextService.new
  end

  def call
    system_prompt = build_system_prompt
    user_message  = build_user_message
    GroqClient.call(system_prompt: system_prompt, user_message: user_message, max_tokens: 400) || fallback
  end

  private

  def build_system_prompt
    parts = [GARY_LINEKER_PERSONA, "", "SCORING RULES:", scoring_rules_text, "", "CURRENT STANDINGS:", @context.leaderboard_text]
    news = @context.news_items(limit: 3)
    if news.any?
      relevant = news.select { |n| relevant_news?(n) }.first(3)
      if relevant.any?
        parts << ""
        parts << "LATEST TOURNAMENT NEWS:"
        relevant.each { |n| parts << "- #{n[:title]}: #{n[:summary]}" }
      end
    end
    parts.join("\n")
  end

  def build_user_message
    home_owner = @match.home_friend_name.presence
    away_owner = @match.away_friend_name.presence

    lines = []
    if home_owner && away_owner && home_owner != away_owner
      lines << "⚡ DIRECT SWEEPSTAKE RIVALRY: #{home_owner}'s #{@match.home_team.name} vs #{away_owner}'s #{@match.away_team.name}"
      lines << ""
    end

    lines << "Provide match preview commentary for: #{@match.home_team.name} vs #{@match.away_team.name} (#{@match.stage})"
    lines << ""
    lines << "PRE-COMPUTED SWEEPSTAKE SCENARIOS:"
    scenario_labels = { home_win: "#{@match.home_team.name} win", draw: "Draw", away_win: "#{@match.away_team.name} win" }
    @scenarios.each do |outcome, data|
      lines << ""
      lines << "IF #{scenario_labels[outcome].upcase}:"
      if data[:team_points].any?
        lines << "  Points awarded: #{data[:team_points].map { |tp| "#{tp[:team_name]} +#{tp[:points_awarded]} (#{tp[:reason]})" }.join(", ")}"
      end
      if data[:friend_deltas].any?
        lines << "  Friend score changes: #{data[:friend_deltas].map { |d| "#{d[:friend]} +#{d[:delta].to_i} → #{d[:new_total].to_i} total" }.join(", ")}"
      end
      if data[:rank_changes].any?
        lines << "  Rank changes: #{data[:rank_changes].map { |rc| "#{rc[:friend]} #{rc[:old_rank]}→#{rc[:new_rank]}" }.join(", ")}"
      end
      lines << "  Leader after: #{data[:new_leader]}"
    end
    lines << ""
    lines << "Write commentary covering each scenario in Gary Lineker's voice. 1-2 sentences per scenario."
    lines.join("\n")
  end

  def scoring_rules_text
    <<~TEXT.strip
      - Group Stage: 0 sweepstake points awarded directly, BUT group results decide who qualifies for the knockouts — the only place points are won. A group win is a step towards qualification and an easier knockout route, so it is never meaningless.
      - Qualifying from the group stage (appearing in any main knockout round): +1 per team
      - Win Last 32 / Last 16 / Quarter-final / Semi-final / Final: +1 per team
      - Win 3rd Place Final: +0.5 (bonus only — appearing here does NOT give the +1 qualification bonus)
      - No multipliers. Each friend's total = sum of all their teams' progression scores.
      - Max possible: 6.0 (champion), runner-up: 5.0, 3rd place winner: 4.5
    TEXT
  end

  def relevant_news?(news_item)
    text = "#{news_item[:title]} #{news_item[:summary]}".downcase
    team_names = [@match.home_team.name, @match.away_team.name].map(&:downcase)
    team_names.any? { |name| text.include?(name) } ||
      %w[world cup injury suspension group final].any? { |kw| text.include?(kw) }
  end

  def fallback
    scenario_labels = { home_win: "#{@match.home_team.name} win", draw: "Draw", away_win: "#{@match.away_team.name} win" }
    parts = @scenarios.filter_map do |outcome, data|
      next if data[:friend_deltas].empty?
      deltas = data[:friend_deltas].map { |d| "#{d[:friend]} +#{d[:delta].to_i}" }.join(", ")
      "#{scenario_labels[outcome]}: #{deltas}"
    end
    parts.any? ? parts.join(" | ") : "#{@match.home_team.name} vs #{@match.away_team.name} — points up for grabs!"
  end

  def compute_cache_key
    self.class.compute_cache_key_for(@match)
  end
end
