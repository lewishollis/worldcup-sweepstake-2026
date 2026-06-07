class UpcomingMatchesInsightService
  BEN_MOTSON_PERSONA = <<~PROMPT.freeze
    You are Ben Botcurdy, an enthusiastic World Cup sweepstake commentator with a flair for drama.

    CRITICAL RULES:
    - You are given pre-computed facts. Report them faithfully. Do not speculate beyond what is provided.
    - Never invent scores, points, or standings not in the data.
    - Be specific: use names, numbers, and positions from the data.
    - Keep the summary to 2-3 sentences.
    - Keep each per-match line to 2-3 sentences maximum.
    - For group stage matches: mention that no sweepstake points are up for grabs, name the favourite, call out one player to watch, and give a sense of whether to expect goals or a tight affair.
    - For knockout matches: focus on sweepstake implications for the owners.
    - Respond ONLY with valid JSON. No markdown, no explanation, no code fences.
  PROMPT

  CACHE_KEY = "upcoming_matches_insight".freeze

  def self.call(matches)
    new(matches).call
  end

  def initialize(matches)
    @matches = matches
  end

  def call
    version = cache_version
    cached = AiInsightCache.fetch(key: CACHE_KEY, version: version) if AiInsightCache.table_exists?
    if cached
      begin
        parsed = JSON.parse(cached, symbolize_names: true)
        return { summary: parsed[:summary], per_match: (parsed[:matches] || {}).transform_keys(&:to_s) }
      rescue JSON::ParserError
        nil
      end
    end

    result = generate
    if result[:summary] && AiInsightCache.table_exists?
      AiInsightCache.store(key: CACHE_KEY, version: version, content: { summary: result[:summary], matches: result[:per_match] }.to_json)
    end
    result
  rescue => e
    Rails.logger.error("UpcomingMatchesInsightService failed: #{e.message}")
    { summary: nil, per_match: {} }
  end

  private

  def generate
    context = TournamentContextService.new
    system_prompt = [BEN_MOTSON_PERSONA, "", "CURRENT STANDINGS:", context.leaderboard_text].join("\n")
    user_message = build_user_message

    raw = GroqClient.call(system_prompt: system_prompt, user_message: user_message, max_tokens: 1200)
    return { summary: nil, per_match: {} } unless raw

    parsed = JSON.parse(raw, symbolize_names: true)
    {
      summary: parsed[:summary],
      per_match: (parsed[:matches] || {}).transform_keys(&:to_s)
    }
  rescue JSON::ParserError => e
    Rails.logger.error("UpcomingMatchesInsightService JSON parse failed: #{e.message} — raw: #{raw}")
    { summary: nil, per_match: {} }
  end

  def build_user_message
    knockout_stages = ['Last 16', 'Quarter-finals', 'Semi-finals', '3rd Place Final', 'Final']
    today = Date.today
    first_match_date = @matches.map { |m| m.start_time.to_date }.min
    tournament_started = today >= first_match_date

    context_line = if tournament_started
      "Today is #{today.strftime('%A, %d %B %Y')}. The tournament is underway."
    else
      "Today is #{today.strftime('%A, %d %B %Y')}. The tournament has NOT started yet — the first match is on #{first_match_date.strftime('%d %B %Y')}. Do NOT say the action continues today."
    end

    lines = ["#{context_line} Provide commentary for upcoming World Cup matches.", ""]
    lines << "Respond in this exact JSON format:"
    lines << '{ "summary": "...", "matches": { "<match_id>": "...", ... } }'
    lines << ""
    lines << "MATCHES:"

    @matches.each do |match|
      home = match.home_team.name
      away = match.away_team.name
      home_owner = match.home_friend_name.presence || "No owner"
      away_owner = match.away_friend_name.presence || "No owner"
      lines << ""
      lines << "match_id: #{match.match_id}"
      lines << "#{home} (#{home_owner}) vs #{away} (#{away_owner}) — #{match.stage} at #{match.start_time&.strftime('%H:%M')}"

      if home_owner != "No owner" && away_owner != "No owner" && home_owner != away_owner
        lines << "  ⚡ DIRECT SWEEPSTAKE RIVALRY: #{home_owner}'s #{home} vs #{away_owner}'s #{away}"
      end

      if knockout_stages.include?(match.stage)
        begin
          scenarios = ScenarioEngine.new(match).call
          scenario_labels = { home_win: "#{home} win", away_win: "#{away} win", draw: "Draw" }
          scenarios.each do |outcome, data|
            next if data[:friend_deltas].empty?
            deltas = data[:friend_deltas].map { |d| "#{d[:friend]} +#{d[:delta].to_i} → #{d[:new_total].to_i}" }.join(", ")
            lines << "  If #{scenario_labels[outcome]}: #{deltas} | Leader: #{data[:new_leader]}"
          end
        rescue => e
          Rails.logger.warn("ScenarioEngine failed for match #{match.id}: #{e.message}")
        end
      end
    end

    lines << ""
    lines << "Write the summary covering today's matches overall, then one sentence per match_id."
    lines.join("\n")
  end

  def cache_version
    match_ids = @matches.map(&:match_id).sort.join(",")
    leaderboard = Group.includes(:teams).order(:id).map { |g| "#{g.id}:#{g.total_points}" }.join("|")
    Digest::SHA256.hexdigest("#{match_ids}|#{leaderboard}")[0, 16]
  end
end
