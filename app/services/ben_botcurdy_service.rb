class BenBotcurdyService
  BEN_MOTSON_PERSONA = <<~PROMPT.freeze
    You are Ben Botcurdy, an enthusiastic World Cup sweepstake commentator with a flair for drama.

    CRITICAL RULES:
    - You are given pre-computed facts. Report them faithfully. Do not speculate beyond what is provided.
    - Never invent alternative outcomes, scores, or standings.
    - Keep responses concise: 2-4 sentences maximum.
    - Be specific: use names, numbers, and positions from the data.
    - ACCURACY: If two players are on the same points, say they are LEVEL or TIED — never say one is "leading" or "ahead".
    - ACCURACY: Only use words like "dominating" or "runaway leader" if the gap is 5+ points.
    - ACCURACY: The gap between 1st and 2nd place is exactly as shown in the standings. Do not exaggerate it.
    - Write naturally and interestingly — no bullet points, no lists, just flowing commentary.
  PROMPT

  def initialize(context_type, context_data = {})
    @context_type = context_type
    @context_data = context_data
  end

  def generate_insight
    if @context_type == :leaderboard
      version = leaderboard_cache_version
      cached = AiInsightCache.fetch(key: "leaderboard_battleground", version: version) if defined?(AiInsightCache) && AiInsightCache.table_exists?
      return cached if cached
    end

    system_prompt = build_system_prompt
    user_message  = build_user_message
    result = GroqClient.call(system_prompt: system_prompt, user_message: user_message, max_tokens: 250) ||
             _call_claude(system_prompt: system_prompt, user_message: user_message) ||
             _fallback_insight

    if @context_type == :leaderboard && result && defined?(AiInsightCache) && AiInsightCache.table_exists?
      AiInsightCache.store(key: "leaderboard_battleground", version: leaderboard_cache_version, content: result)
    end

    result
  end

  private

  def build_system_prompt
    ctx = TournamentContextService.new
    parts = [BEN_MOTSON_PERSONA, "", "CURRENT STANDINGS:", ctx.leaderboard_text]
    news = ctx.news_items(limit: 5)
    if news.any?
      parts << ""
      parts << "LATEST TOURNAMENT NEWS:"
      news.each { |n| parts << "- #{n[:title]}: #{n[:summary]}" }
    end
    parts.join("\n")
  end

  def build_user_message
    case @context_type
    when :leaderboard then build_leaderboard_message
    when :matches     then build_matches_message
    end
  end

  def build_leaderboard_message
    ctx = TournamentContextService.new
    pivotal = ctx.pivotal_matches(count: 3)
    lines = ["Provide a leaderboard state-of-play commentary covering:", ""]
    lines << "1. Who is leading and by how much"
    lines << "2. The 2-3 most pivotal upcoming matches and their sweepstake implications"
    lines << ""
    if pivotal.any?
      lines << "PIVOTAL UPCOMING MATCHES (pre-computed scenarios):"
      pivotal.each do |match|
        scenarios = ScenarioEngine.new(match).call
        lines << ""
        lines << "#{match.home_team.name} vs #{match.away_team.name} (#{match.stage}, #{match.start_time&.strftime("%d %b")}):"
        scenario_labels = { home_win: "#{match.home_team.name} win", away_win: "#{match.away_team.name} win", draw: "Draw" }
        scenarios.each do |outcome, data|
          next if data[:friend_deltas].empty?
          deltas = data[:friend_deltas].map { |d| "#{d[:friend]} +#{d[:delta].to_i}" }.join(", ")
          lines << "  If #{scenario_labels[outcome]}: #{deltas} | Leader: #{data[:new_leader]}"
        end
      end
    end
    lines << ""
    lines << "Write 3-4 sentences of exciting leaderboard commentary in Ben Botcurdy's voice."
    lines.join("\n")
  end

  def build_matches_message
    matches    = @context_data[:matches] || []
    filter_type = @context_data[:filter_type]
    lines = ["Provide commentary for #{filter_type} matches:", ""]
    matches.first(3).each do |match|
      if filter_type == "MidEvent"
        lines << "LIVE: #{match.home_team.name} #{match.home_score}–#{match.away_score} #{match.away_team.name} (#{match.stage})"
      elsif filter_type == "PostEvent"
        winner = match.winner == "home" ? match.home_team.name : match.away_team.name
        lines << "RESULT: #{match.home_team.name} #{match.home_score}–#{match.away_score} #{match.away_team.name} — #{winner} wins (#{match.stage})"
      else
        lines << "UPCOMING: #{match.home_team.name} vs #{match.away_team.name} at #{match.start_time&.strftime("%H:%M")} (#{match.stage})"
      end
    end
    lines << ""
    lines << "Write 1-2 punchy sentences of commentary. Be specific with team names."
    lines.join("\n")
  end

  def _call_claude(system_prompt:, user_message:)
    api_key = ENV["ANTHROPIC_API_KEY"] || Rails.application.credentials.dig(:anthropic, :api_key)
    return nil unless api_key

    uri = URI("https://api.anthropic.com/v1/messages")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl    = true
    http.read_timeout = 15

    request = Net::HTTP::Post.new(uri.path)
    request["x-api-key"]         = api_key
    request["anthropic-version"] = "2023-06-01"
    request["content-type"]      = "application/json"
    request.body = {
      model:      "claude-haiku-4-5-20251001",
      max_tokens: 250,
      system:     system_prompt,
      messages:   [{ role: "user", content: user_message }]
    }.to_json

    response = http.request(request)
    JSON.parse(response.body).dig("content", 0, "text")
  rescue => e
    Rails.logger.error("Claude API fallback failed: #{e.message}")
    nil
  end

  def _fallback_insight
    "The sweepstake is heating up! Stay tuned for more commentary as the tournament unfolds."
  end

  def leaderboard_cache_version
    totals = Group.includes(:teams).order(:id).map { |g| "#{g.id}:#{g.total_points}" }.join("|")
    Digest::SHA256.hexdigest(totals)[0, 16]
  end
end
