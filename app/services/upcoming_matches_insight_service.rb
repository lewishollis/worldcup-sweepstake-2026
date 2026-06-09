class UpcomingMatchesInsightService
  CACHE_KEY = "upcoming_matches_insight".freeze

  def self.call(matches)
    new(matches).call
  end

  def initialize(matches)
    @matches = matches
  end

  def call
    version = cache_version
    if AiInsightCache.table_exists?
      cached = AiInsightCache.fetch(key: CACHE_KEY, version: version)
      return cached if cached
    end

    result = generate
    AiInsightCache.store(key: CACHE_KEY, version: version, content: result) if result && AiInsightCache.table_exists?
    result
  rescue => e
    Rails.logger.error("UpcomingMatchesInsightService failed: #{e.message}")
    nil
  end

  private

  def generate
    context = TournamentContextService.new
    system_prompt = build_system_prompt(context)
    user_message  = build_user_message

    GroqClient.call(system_prompt: system_prompt, user_message: user_message, max_tokens: 600) ||
      "Check the standings for today's sweepstake picture."
  end

  def build_system_prompt(context)
    [
      "You are a sweepstake analyst writing a casual message to friends about today's World Cup matches.",
      "",
      "RULES:",
      "- Write like you're texting a group chat. Casual, warm, a bit of banter.",
      "- Be specific: use exact names and points from the data provided.",
      "- Accuracy above all: never invent scores, points, or positions not in the data.",
      "- No bullet points, no markdown, no lists. Just flowing paragraphs.",
      "- Start with something casual like 'Soooo, today...' or similar.",
      "- Keep it to 3-5 paragraphs.",
      "",
      "CURRENT STANDINGS:",
      context.leaderboard_text
    ].join("\n")
  end

  def build_user_message
    today = Date.today
    first_match_date = @matches.map { |m| m.start_time.to_date }.min
    tournament_started = today >= first_match_date

    context_line = if tournament_started
      "Today is #{today.strftime('%A, %d %B %Y')}. The tournament is underway."
    else
      "Today is #{today.strftime('%A, %d %B %Y')}. The tournament hasn't started yet — first match is #{first_match_date.strftime('%d %B %Y')}. Don't say the action continues today."
    end

    lines = [context_line, "", "TODAY'S MATCHES:"]

    @matches.each do |match|
      home      = match.home_team.name
      away      = match.away_team.name
      home_owner = match.home_friend_name.presence
      away_owner = match.away_friend_name.presence
      lines << ""
      lines << "#{home} (#{home_owner || 'unowned'}) vs #{away} (#{away_owner || 'unowned'}) — #{match.stage} at #{match.start_time&.strftime('%H:%M')}"

      if Team::KNOCKOUT_STAGES.include?(match.stage)
        begin
          scenarios = ScenarioEngine.new(match).call
          scenario_labels = { home_win: "#{home} win", away_win: "#{away} win", draw: "Draw" }
          scenarios.each do |outcome, data|
            next if data[:friend_deltas].empty?
            deltas = data[:friend_deltas].map { |d| "#{d[:friend]} +#{d[:delta].to_i} → #{d[:new_total].to_i}pts" }.join(", ")
            lines << "  If #{scenario_labels[outcome]}: #{deltas} | Leader: #{data[:new_leader]}"
          end
        rescue => e
          Rails.logger.warn("ScenarioEngine failed for match #{match.id}: #{e.message}")
        end
      else
        lines << "  (Group stage — no sweepstake points awarded today)"
      end
    end

    lines << ""
    lines << "Write a casual group-chat-style message explaining what each person needs from today's matches and why. Focus on the sweepstake stakes. Be specific with names and numbers."
    lines.join("\n")
  end

  def cache_version
    match_ids  = @matches.map(&:match_id).sort.join(",")
    leaderboard = Group.includes(teams: [:home_matches, :away_matches]).order(:id).map { |g| "#{g.id}:#{g.total_points}" }.join("|")
    status     = TournamentContextService.new.tournament_status.to_s
    Digest::SHA256.hexdigest("#{match_ids}|#{leaderboard}|#{status}")[0, 16]
  end
end
