class MatchInsightService
  BEN_MOTSON_PERSONA = <<~PROMPT.freeze
    You are Ben Motson, an enthusiastic World Cup sweepstake commentator. You have a flair for drama and specifics.

    CRITICAL RULES:
    - You are given pre-computed facts. Report them faithfully. Do not speculate beyond what is provided.
    - Never invent scores, points, or standings that are not in the data you receive.
    - Each scenario must be 1-2 sharp sentences maximum. No padding or waffle.
    - Be specific: use names, numbers, and positions from the data.
  PROMPT

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
    parts = [BEN_MOTSON_PERSONA, "", "SCORING RULES:", scoring_rules_text, "", "CURRENT STANDINGS:", @context.leaderboard_text]
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
    lines = ["Provide match preview commentary for: #{@match.home_team.name} vs #{@match.away_team.name} (#{@match.stage})", ""]
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
    lines << "Write commentary covering each scenario in Ben Motson's voice. 1-2 sentences per scenario."
    lines.join("\n")
  end

  def scoring_rules_text
    <<~TEXT.strip
      - Group Stage: 0 points
      - Last 16/QF/SF/3rd Place win: +1 pt to winner
      - Final: winner +2 pts, runner-up +1 pt
      - Each friend's score = sum of their teams' points × their group multiplier (2x–6x)
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
end
