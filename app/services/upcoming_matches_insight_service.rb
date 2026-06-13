class UpcomingMatchesInsightService
  CACHE_KEY = "upcoming_matches_insight".freeze
  TIME_ZONE = "Europe/London".freeze
  # Folded into the cache version so changing the persona regenerates any
  # previously cached insight written in the old voice.
  PERSONA_VERSION = "gary-lineker-v5".freeze

  def self.call(matches)
    new(matches).call
  end

  def initialize(matches)
    @matches = next_match_day_matches(matches)
  end

  def call
    return nil if @matches.empty?

    version = cache_version
    if AiInsightCache.table_exists?
      cached = AiInsightCache.fetch(key: CACHE_KEY, version: version)
      return cached if cached
    end

    result = generate
    if result
      AiInsightCache.store(key: CACHE_KEY, version: version, content: result) if AiInsightCache.table_exists?
      result
    else
      # Fallback is deliberately not cached so a real insight can replace it next request
      "Check the standings for today's sweepstake picture."
    end
  rescue => e
    Rails.logger.error("UpcomingMatchesInsightService failed: #{e.message}")
    nil
  end

  private

  # The insight covers a single match day: the next UK date (today or later) with a fixture
  def next_match_day_matches(matches)
    dated = matches.select { |m| m.start_time.present? }
    today = Time.current.in_time_zone(TIME_ZONE).to_date
    next_day = dated.map { |m| m.start_time.in_time_zone(TIME_ZONE).to_date }
                    .select { |d| d >= today }
                    .min
    return [] unless next_day

    dated.select { |m| m.start_time.in_time_zone(TIME_ZONE).to_date == next_day }
         .sort_by(&:start_time)
  end

  def match_day
    @matches.first.start_time.in_time_zone(TIME_ZONE).to_date
  end

  # Matches that finished in the last 24 hours, regardless of which UK calendar
  # date they fall on — covers overnight fixtures that crossed midnight.
  def recently_finished_matches
    @recently_finished_matches ||= Match.where(status: "PostEvent")
                                         .where(start_time: 24.hours.ago..Time.current)
                                         .includes(:home_team, :away_team)
                                         .order(:start_time)
                                         .to_a
  end

  def generate
    snapshot      = GameStateSnapshot.new
    system_prompt = build_system_prompt(snapshot)
    user_message  = build_user_message(snapshot)

    GroqClient.call(system_prompt: system_prompt, user_message: user_message, max_tokens: 600)
  end

  def build_system_prompt(context_or_snapshot = GameStateSnapshot.new)
    leaderboard = if context_or_snapshot.respond_to?(:leaderboard_text)
                    context_or_snapshot.leaderboard_text
                  else
                    TournamentContextService.new.leaderboard_text
                  end
    [
      "You are Gary Lineker, the former England striker turned BBC Match of the Day presenter, sending a short message to friends about upcoming World Cup matches in their sweepstake.",
      "Voice: warm, articulate and quick with a dry, gentle wit — the odd pun and a self-deprecating nod to your playing days are welcome. Polished but never pompous, and clean enough for a family group chat.",
      "",
      "HOW THE SWEEPSTAKE SCORING WORKS — READ CAREFULLY:",
      "- Points are only awarded in the KNOCKOUT stages: +1 for a team reaching the main knockout bracket, then +1 for each knockout win (the 3rd-place final is worth +0.5).",
      "- Group-stage matches award no points directly — but they are far from pointless. Group results decide WHO reaches the knockouts, which is the only place points are won.",
      "- So a group win matters enormously: for the smaller teams, winning is how they reach the knockouts at all and bank that first point; for the big teams, topping the group means an easier knockout route and a better shot at racking up wins (and points) later.",
      "- Never call a group match meaningless or pointless. Treat group results as the springboard to the knockout points.",
      "",
      "RULES:",
      "- Never write your own name or sign the message — no by-line, no presenter name (not 'Gary Lineker', not 'John Botson'). Just write the message itself.",
      "- World rankings may appear next to team names (e.g. 'world #5'); lower is stronger. You MAY forecast: call out the favourite, say a strong side should go through, and judge whether a group looks kind or tough — but base every such call ONLY on the rankings and results provided, never on outside knowledge. Hard facts (guaranteed/cannot finish top 2) are certainties; everything else is a forecast, so phrase it as one ('should', 'look favourites', 'likely').",
      "- Use the supplied 'What tonight's result does' lines to tell people where a result moves a team — e.g. 'a win puts them top of the group' — and tie that to the owner's chances of reaching the knockouts.",
      "- Name the group favourites and mention each side's run-in (their remaining group games and how tough the opponents are by ranking) when it's relevant.",
      "- Balance the football and the sweepstake: cover both how the match looks and what it means for the owners.",
      "- Length: a short paragraph per match, plus a brief opener and sign-off. Keep it tight, not a thesis.",
      "- Be specific: use exact names and points from the data provided.",
      "- Accuracy above all: never invent scores, points, or positions not in the data. Your voice changes the wording, never the facts.",
      "- ONLY discuss the matches listed in the message. Never mention any other fixture or matchup.",
      "- Every match comes with its exact date and kick-off time. Never state or imply a different date or day.",
      "- If any matches are listed under MATCHES ALREADY PLAYED, open with one brief sentence acknowledging they've happened and pointing people to the highlights. Never mention the score, goalscorers, winner, or result of these matches under any circumstances.",
      "- No bullet points, no markdown, no lists. Just flowing prose.",
      "",
      "CURRENT STANDINGS (points totals only — do not list a person's other teams as if they are playing):",
      leaderboard
    ].join("\n")
  end

  def build_user_message(snapshot = GameStateSnapshot.new)
    today = Time.current.in_time_zone(TIME_ZONE).to_date
    day   = match_day
    day_label = day == today ? "today (#{day.strftime('%A %d %B %Y')})" : day.strftime("%A %d %B %Y")
    tournament_started = TournamentContextService.new.tournament_status != :not_started

    context_line = if tournament_started
      "Today is #{today.strftime('%A, %d %B %Y')}. The tournament is underway."
    else
      "Today is #{today.strftime('%A, %d %B %Y')}. The tournament hasn't started yet — no matches have been played. Don't describe any action as already happening."
    end

    lines = [context_line]

    if recently_finished_matches.any?
      lines << ""
      lines << "MATCHES ALREADY PLAYED (DO NOT REVEAL RESULTS):"
      recently_finished_matches.each do |match|
        kickoff = match.start_time.in_time_zone(TIME_ZONE)
        lines << "- #{match.home_team.name} vs #{match.away_team.name} — #{match.stage} — #{kickoff.strftime('%A %d %B %Y, %H:%M')} UK time"
      end
    end

    lines << ""
    lines << "MATCHES ON #{day.strftime('%A %d %B %Y').upcase}#{day == today ? ' (TODAY)' : ''}:"

    @matches.each do |match|
      home       = match.home_team.name
      away       = match.away_team.name
      # Derive ownership live — the denormalised friend-name columns on Match go
      # stale when group assignments change between API syncs
      home_owner = owner_name(match.home_team)
      away_owner = owner_name(match.away_team)
      kickoff    = match.start_time.in_time_zone(TIME_ZONE)
      lines << ""
      lines << "#{home} (#{home_owner || 'unowned'}) vs #{away} (#{away_owner || 'unowned'}) — #{match.stage} — #{kickoff.strftime('%A %d %B %Y, %H:%M')} UK time"

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
        group_context = snapshot.group_context_text(match)
        lines << group_context.lines.map { |l| "  #{l.chomp}" }.join("\n") if group_context
      end
    end

    lines << ""
    lines << "Write the group-chat message about the matches on #{day_label}: a short paragraph per match plus a brief opener and sign-off. For each game, weave together how it looks (favourites by ranking, who should progress, how kind the group/run-in is) and what it means for the owners — including where tonight's result would move a team in the table and their chances of reaching the knockouts. Forecasts are welcome but must come only from the rankings and results above; never invent anything. Only mention the matches listed above."
    lines.join("\n")
  end

  def owner_name(team)
    team.groups.first&.friend&.name
  end

  def cache_version
    match_ids   = @matches.map(&:match_id).sort.join(",")
    recent_ids  = recently_finished_matches.map(&:match_id).sort.join(",")
    leaderboard = Group.includes(teams: [:home_matches, :away_matches]).order(:id).map { |g| "#{g.id}:#{g.total_points}" }.join("|")
    status      = TournamentContextService.new.tournament_status.to_s
    today       = Time.current.in_time_zone(TIME_ZONE).to_date.iso8601
    Digest::SHA256.hexdigest("#{PERSONA_VERSION}|#{today}|#{match_ids}|#{recent_ids}|#{leaderboard}|#{status}|#{GameStateSnapshot.data_version}")[0, 16]
  end
end
