class UpcomingMatchesInsightService
  CACHE_KEY = "upcoming_matches_insight".freeze
  # Remembers the last football fact served so the next render never repeats it.
  # Kept OUT of the main cached body so the fact varies on every page view even
  # while the briefing itself is cached.
  FOOTBALL_FACT_KEY = "upcoming_matches_football_fact".freeze
  FOOTBALL_FACT_VERSION = "v1".freeze
  TIME_ZONE = "Europe/London".freeze
  # Folded into the cache version so changing the persona regenerates any
  # previously cached insight written in the old voice.
  PERSONA_VERSION = "gary-lineker-v11".freeze
  # Owners based in Vietnam — matches involving their teams also show Vietnam time.
  VIETNAM_FRIENDS = ["Richard", "Nhiên"].freeze
  VIETNAM_TIME_ZONE = "Asia/Ho_Chi_Minh".freeze

  # Curated, verified, evergreen football facts. Appended verbatim as the sign-off
  # so the closing trivia is always TRUE — never left to the model to invent.
  # Keep these factual and timeless; add freely, but each must be checkably true.
  FOOTBALL_FACTS = [
    "Brazil are the only men's national team to have played at every World Cup finals.",
    "The first men's World Cup, in 1930, was hosted and won by Uruguay.",
    "Miroslav Klose is the men's World Cup all-time top scorer, with 16 goals.",
    "Pelé is the only player to have won three men's World Cups: 1958, 1962 and 1970.",
    "Only eight nations have ever won the men's World Cup.",
    "Germany have reached more men's World Cup finals than any other nation.",
    "The 2026 World Cup is the first to feature 48 teams.",
    "The 2026 World Cup is co-hosted by Canada, Mexico and the USA — its first three hosts.",
    "Cristiano Ronaldo is the only man to have scored at five different World Cups.",
    "The 1994 World Cup final was the first to be decided by a penalty shootout."
  ].freeze

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
      # Append a fresh fact even on a cache hit, so it differs every render.
      return with_football_fact(cached) if cached
    end

    result = generate
    if result
      AiInsightCache.store(key: CACHE_KEY, version: version, content: result) if AiInsightCache.table_exists?
      with_football_fact(result)
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

    message = GroqClient.call(system_prompt: system_prompt, user_message: user_message, max_tokens: 600)
    # Return the briefing body only — the verified football fact is appended later
    # (per render, not per cache) so it stays fresh every time. See #with_football_fact.
    message&.strip
  end

  # Appends a verified, true fact as the sign-off. Done outside the cache so the
  # fact changes on every render even when the briefing body is cached.
  def with_football_fact(body)
    "#{body.strip}\n\nFootball fact: #{next_football_fact}"
  end

  # A curated fact that is never the same as the one served on the previous render.
  def next_football_fact
    return FOOTBALL_FACTS.sample unless AiInsightCache.table_exists?

    previous = AiInsightCache.fetch(key: FOOTBALL_FACT_KEY, version: FOOTBALL_FACT_VERSION)
    fact = (FOOTBALL_FACTS - [previous]).sample
    AiInsightCache.store(key: FOOTBALL_FACT_KEY, version: FOOTBALL_FACT_VERSION, content: fact)
    fact
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
      "- Then ONE paragraph per match (2–5 short sentences), in this order: (1) the two teams, their owners, and the kick-off time; (2) if an opening-match note is supplied, mention it's their first group game; (3) the group favourites by ranking, with a brief underdog/upset angle when the ranking gap is wide; (4) what a win or a draw does for the table and for qualification; (5) optionally ONE brief, well-known historical note about a team in the fixture. Do NOT list a side's upcoming fixtures UNLESS a 'final group game (could decide their fate)' line is supplied for them — only then, mention who they face next.",
      "- Do NOT write a sign-off or good-luck line. End after the final match — a football fact is added automatically.",
      "",
      "STYLE EXAMPLE — copy this structure and plain tone; do NOT reuse its teams or names:",
      "\"\"\"",
      "The tournament continues, with two matches today.",
      "First up, Germany, owned by Emma, face Curaçao, owned by Jamie, at 18:00 UK time. It's the opening Group E match for both sides. Germany are the group's top-ranked side and clear favourites; a Curaçao win would be a major upset on the rankings. A win for Germany would put them top of the group; a draw leaves both level on points and still in with a chance of going through. Germany have reached more World Cup finals than any other nation.",
      "Later, Netherlands, owned by Richard, take on Japan, owned by Bea, at 21:00 UK time / 03:00 Vietnam time. It's the opening Group F fixture, and on the rankings the two strongest sides in the group. A win for either would put them in a strong early position to qualify; a draw leaves both level at the top.",
      "\"\"\"",
      "",
      "RULES:",
      "- Never write your own name or sign the message — no by-line, no presenter name (not 'Gary Lineker', not 'John Botson'). Just write the briefing.",
      "- Be concise and scannable: short sentences, and state each point ONCE — never restate the same idea in different words.",
      "- Combine the result outcomes into ONE short sentence where you can, e.g. 'A win for either side would put them top of the group; a draw leaves both level on points and still in with a chance of going through.' Don't write a separate clause for each team and each outcome.",
      "- State the qualification picture plainly, using the supplied notes: when teams are level on points, say they're level on points (never 'among the leaders' or similar vagueness); when a side still has a chance of reaching the next round, say so once; when it's a hard fact (guaranteed through, or out), state that certainty. Don't repeat the same status more than once per match.",
      "- Include each match's kick-off time exactly as given. When both a UK time and a Vietnam time are shown, include both.",
      "- No hype or filler. Avoid words and phrases like 'thrilling', 'mouth-watering', 'cracking', 'feast', 'giant leap', 'looking to make a statement', 'football gods'.",
      "- Refer to ownership plainly as 'Team, owned by Friend'.",
      "- World rankings may appear next to team names (e.g. 'world #5'); lower is stronger. You MAY forecast from them — call the favourite, say who should go through, judge a kind or tough group, and flag a likely upset when a far lower-ranked side could win. Phrase forecasts as forecasts ('should', 'favourites'); hard facts (guaranteed/cannot finish top 2) are certainties.",
      "- COLOUR you MAY add from your own football knowledge: one brief, well-known historical note about a team in the fixture (a past tournament, a debut, a notable record) and light context. Keep it to a single short note per match, and only facts you are confident are genuinely true — if unsure, leave it out. Never invent specific statistics, records, scores, or results.",
      "- Use the supplied 'What tonight's result does' lines to say where a result moves a team — e.g. 'a win puts them top of the group'. Only mention a side's upcoming fixtures when a 'final group game (could decide their fate)' line is supplied — otherwise leave them out.",
      "- Balance the football and the sweepstake, but briefly.",
      "- HARD FACTS come ONLY from the data, never from memory or invention: current scores, points, positions, the rankings and qualification flags supplied, which fixtures exist, and kick-off times/dates. ONLY discuss the matches listed; never mention another fixture. (The historical colour above is the only thing you may add from outside the data.)",
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
      lines << ""
      lines << "#{home} (#{home_owner || 'unowned'}) vs #{away} (#{away_owner || 'unowned'}) — #{match.stage} — #{kickoff_label(match, [home_owner, away_owner])}"

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
    lines << "Write the briefing for #{day_label}, following the required structure exactly: one short intro line, then one paragraph per match (teams + owners + kick-off → opening-match note if supplied → favourites/ranking with any upset angle → what a win or draw does for the table and qualification → one brief historical note if you have a true one). Keep it concise and scannable, state each point once, no hype or filler. Hard facts (scores, points, positions, fixtures, times) only from the data above; brief historical colour may come from your own knowledge if you are sure it's true. Do NOT write a sign-off — a football fact is added automatically. Only the matches listed above."
    lines.join("\n")
  end

  def owner_name(team)
    team.groups.first&.friend&.name
  end

  # Kick-off shown in UK time, plus Vietnam time when a Vietnam-based owner
  # (Richard or Nhiên) has a team in the match.
  def kickoff_label(match, owners)
    uk    = match.start_time.in_time_zone(TIME_ZONE)
    label = "#{uk.strftime('%A %d %B %Y, %H:%M')} UK time"
    if owners.compact.any? { |o| VIETNAM_FRIENDS.include?(o) }
      vn = match.start_time.in_time_zone(VIETNAM_TIME_ZONE)
      label += " / #{vn.strftime('%H:%M')} Vietnam time"
    end
    label
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
