class BenMotsonService
  BEN_MOTSON_PERSONA = <<~PROMPT.freeze
    You are Ben Motson, an enthusiastic World Cup sweepstake commentator with a flair for drama.

    CRITICAL RULES:
    - You are given pre-computed facts. Report them faithfully. Do not speculate beyond what is provided.
    - Never invent alternative outcomes, scores, or standings.
    - Keep responses concise: 2-4 sentences maximum.
    - Be specific: use names, numbers, and positions from the data.
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
    result = GroqClient.call(system_prompt: system_prompt, user_message: user_message, max_tokens: 250) || fallback_insight

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
    lines << "Write 3-4 sentences of exciting leaderboard commentary in Ben Motson's voice."
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

  def fallback_insight
    case @context_type
    when :leaderboard
      groups = Group.includes(:friend, :teams).sort_by { |g| -g.total_points }
      leader = groups.first
      second = groups[1]
      upcoming = Match.where(status: "PreEvent").where.not(stage: "Group Stage").where("start_time > ?", Time.current).order(:start_time).first
      if upcoming
        home_friend = upcoming.home_team.groups.first&.friend&.name
        away_friend = upcoming.away_team.groups.first&.friend&.name
        "#{leader.friend&.name} leads with #{leader.total_points.to_i} points! Next up: #{upcoming.home_team.name}#{home_friend ? " (#{home_friend})" : ""} faces #{upcoming.away_team.name}#{away_friend ? " (#{away_friend})" : ""} in the #{upcoming.stage}. Everything could change!"
      elsif second
        gap = leader.total_points - second.total_points
        "#{leader.friend&.name} is dominating with #{leader.total_points.to_i} points, #{gap.to_i} ahead of #{second.friend&.name}. Can anyone catch them?"
      else
        "#{leader.friend&.name} is leading with #{leader.total_points.to_i} points! The race is on!"
      end
    when :matches
      filter = @context_data[:filter_type]
      matches = @context_data[:matches] || []
      case filter
      when "MidEvent"
        live = matches.select { |m| m.status == "MidEvent" }.first
        live ? "#{live.home_team.name} #{live.home_score}–#{live.away_score} #{live.away_team.name} and more matches in progress!" : "#{matches.count} matches LIVE!"
      when "PostEvent"
        ko = matches.reject { |m| m.stage == "Group Stage" }.first
        ko ? "#{ko.home_team.name} #{ko.home_score}–#{ko.away_score} #{ko.away_team.name}. #{ko.winner == "home" ? ko.home_team.name : ko.away_team.name} marches on!" : "#{matches.count} matches completed."
      when "PreEvent"
        upcoming = matches.first
        upcoming ? "#{upcoming.home_team.name} vs #{upcoming.away_team.name} kicks off soon!" : "#{matches.count} matches coming up."
      end
    end
  end

  def leaderboard_cache_version
    totals = Group.includes(:teams).order(:id).map { |g| "#{g.id}:#{g.total_points}" }.join("|")
    Digest::SHA256.hexdigest(totals)[0, 16]
  end
end
