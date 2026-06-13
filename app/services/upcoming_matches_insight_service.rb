class UpcomingMatchesInsightService
  CACHE_KEY = "upcoming_matches_insight".freeze
  TIME_ZONE = "Europe/London".freeze
  # Folded into the cache version so changing the persona regenerates any
  # previously cached insight written in the old voice.
  PERSONA_VERSION = "gary-lineker-v6".freeze

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
      "You write 'John Botson' — the daily sweepstake briefing — in the understated, economical style of Gary Lineker presenting Match of the Day. Clear, natural, lightly warm. Never hyped-up or flowery.",
      "",
      "SCORING (brief): points are only won in the KNOCKOUT stages (+1 for reaching the main knockout bracket, +1 per knockout win, 3rd-place final +0.5). Group games award no points directly, but they decide who qualifies — so a group win matters; never call a group match meaningless or pointless.",
      "",
      "STRUCTURE — follow it exactly:",
      "- One short intro line.",
      "- Then ONE short paragraph per match, in this order: (1) the two teams and their owners; (2) the group favourites by ranking; (3) what a win or a draw does — who goes top, who stays in contention; (4) each side's run-in (their remaining group games).",
      "- One short sign-off line.",
      "",
      "STYLE EXAMPLE — copy this structure and plain tone; do NOT reuse its teams or names:",
      "\"\"\"",
      "The tournament is underway, with two matches today.",
      "First up, Qatar, owned by Ben, face Switzerland, owned by Nhiên. Switzerland and Canada are the group favourites on world ranking. Qatar go top with a win and stay in contention; Switzerland go top with a win, and a draw keeps both near the top. Qatar still have Canada and Bosnia and Herz. to play; Switzerland face the same two.",
      "Later, Brazil, owned by Aimee, take on Morocco, owned by Bea — both among the favourites to top their group. Either goes top with a win; a draw keeps both in contention. Brazil still have Haiti and Scotland to come; Morocco face the same pair.",
      "Best of luck to all owners.",
      "\"\"\"",
      "",
      "RULES:",
      "- Never write your own name or sign the message — no by-line, no presenter name (not 'Gary Lineker', not 'John Botson'). Just write the briefing.",
      "- Be concise and scannable: short sentences, and state each point ONCE — never restate the same idea in different words.",
      "- No hype or filler. Avoid words and phrases like 'thrilling', 'mouth-watering', 'cracking', 'feast', 'giant leap', 'looking to make a statement', 'football gods'.",
      "- Refer to ownership plainly as 'Team, owned by Friend'.",
      "- World rankings may appear next to team names (e.g. 'world #5'); lower is stronger. You MAY forecast from them — call the favourite, say who should go through, judge a kind or tough group — but ONLY from the rankings and results provided, never outside knowledge. Phrase forecasts as forecasts ('should', 'favourites'); hard facts (guaranteed/cannot finish top 2) are certainties.",
      "- Use the supplied 'What tonight's result does' lines to say where a result moves a team — e.g. 'a win puts them top of the group' — and tie it to qualifying. Mention each side's run-in plainly ('still have X and Y to play').",
      "- Balance the football and the sweepstake, but briefly.",
      "- Accuracy: never invent scores, points, or positions not in the data — and never invent fixtures or rankings. ONLY discuss the matches listed; never mention another fixture.",
      "- Every match comes with its exact date and kick-off time. Never state or imply a different date or day.",
      "- If any matches are listed under MATCHES ALREADY PLAYED, acknowledge them in one short line pointing to the highlights. Never mention the score, goalscorers, winner, or result of these matches.",
      "- No markdown, no lists. Plain paragraphs only.",
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
    lines << "Write the briefing for #{day_label}, following the required structure exactly: one short intro line, then one short paragraph per match (teams + owners → group favourites → what a win or draw does → the run-in), then a one-line sign-off. Keep it concise and scannable, state each point once, no hype or filler. Forecasts only from the rankings and results above; never invent anything. Only the matches listed above."
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
