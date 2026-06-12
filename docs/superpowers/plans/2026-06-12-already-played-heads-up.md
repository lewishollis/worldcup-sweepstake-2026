# "Already Played" Heads-Up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** John Botson's upcoming-matches preview acknowledges any matches that finished within the last 24 hours (e.g. an overnight fixture), telling friends to check the highlights — without ever revealing the score, goalscorers, winner, or result.

**Architecture:** `UpcomingMatchesInsightService` gains a new private `recently_finished_matches` method that queries `Match` directly for `PostEvent` matches in the last 24 hours (same direct-DB-query pattern `TournamentContextService` already uses — no controller changes needed). This feeds a new "MATCHES ALREADY PLAYED (DO NOT REVEAL RESULTS)" section in the prompt, a new system-prompt rule telling the model how to handle it, and a cache-version input so the heads-up appears/disappears automatically as matches enter/exit the 24h window.

**Tech Stack:** Ruby on Rails 7.1, Minitest (tests run in transactions, `ActiveSupport::Testing::TimeHelpers` for `travel_to`)

---

## File Structure

**Modified files:**
- `app/services/upcoming_matches_insight_service.rb` — add `recently_finished_matches`, update `build_user_message`, `build_system_prompt`, `cache_version`
- `test/services/upcoming_matches_insight_service_test.rb` — three new tests

No new files. This is a single-file change plus its test file, in line with the existing service's structure.

---

## Task 1: Add `recently_finished_matches` and the "MATCHES ALREADY PLAYED" prompt section

**Files:**
- Modify: `app/services/upcoming_matches_insight_service.rb`
- Test: `test/services/upcoming_matches_insight_service_test.rb`

- [ ] **Step 1: Write the failing test**

Add this test to `test/services/upcoming_matches_insight_service_test.rb`, just before the final `end` of the class (after the `"generated insight is cached but the fallback is not"` test):

```ruby
  test "prompt notes recently finished matches without revealing the score" do
    korea   = Team.create!(name: "Korea Republic", flag_url: "https://x.com/kr.svg")
    czechia = Team.create!(name: "Czechia", flag_url: "https://x.com/cz.svg")
    Match.create!(
      home_team: korea, away_team: czechia, stage: "Group Stage", status: "PostEvent",
      match_id: "umis-finished-1", home_score: 2, away_score: 1, winner: "home",
      start_time: Time.zone.local(2026, 6, 10, 2, 0, 0)
    )

    service = UpcomingMatchesInsightService.new([@tomorrow_match])
    prompt = service.send(:build_user_message)

    assert_includes prompt, "MATCHES ALREADY PLAYED (DO NOT REVEAL RESULTS):"
    assert_includes prompt, "Korea Republic vs Czechia — Group Stage — Wednesday 10 June 2026, 02:00 UK time"
    refute_includes prompt, "2-1", "the score must never appear in the prompt"
  end

  test "prompt omits the already-played section when nothing has finished recently" do
    service = UpcomingMatchesInsightService.new([@tomorrow_match])
    prompt = service.send(:build_user_message)

    refute_includes prompt, "MATCHES ALREADY PLAYED"
  end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/services/upcoming_matches_insight_service_test.rb -n "/recently_finished_matches|already_played/"
```

Expected: 1 failure (the first test) — `assert_includes` fails because `"MATCHES ALREADY PLAYED (DO NOT REVEAL RESULTS):"` is not in the prompt. The second test passes already (the section doesn't exist yet, so it's trivially absent) — that's fine, it documents the no-op case and will keep passing after Step 3.

- [ ] **Step 3: Implement `recently_finished_matches` and update `build_user_message`**

In `app/services/upcoming_matches_insight_service.rb`, add this new private method directly after `match_day`:

```ruby
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
```

Then update `build_user_message` — replace:

```ruby
    lines = [context_line, "", "MATCHES ON #{day.strftime('%A %d %B %Y').upcase}#{day == today ? ' (TODAY)' : ''}:"]
```

with:

```ruby
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/services/upcoming_matches_insight_service_test.rb
```

Expected: all tests pass (the two new ones plus all existing ones, which are unaffected since `recently_finished_matches` is empty for their fixtures).

- [ ] **Step 5: Commit**

```bash
git add app/services/upcoming_matches_insight_service.rb test/services/upcoming_matches_insight_service_test.rb
git commit -m "feat: list recently finished matches (no scores) in John Botson's prompt"
```

---

## Task 2: Tell John Botson never to reveal results of already-played matches

**Files:**
- Modify: `app/services/upcoming_matches_insight_service.rb`
- Test: `test/services/upcoming_matches_insight_service_test.rb`

- [ ] **Step 1: Write the failing test**

Add this test to `test/services/upcoming_matches_insight_service_test.rb`, after the test added in Task 1:

```ruby
  test "system prompt instructs John Botson never to reveal results of already-played matches" do
    service = UpcomingMatchesInsightService.new([@tomorrow_match])
    prompt = service.send(:build_system_prompt, TournamentContextService.new)

    assert_includes prompt, "MATCHES ALREADY PLAYED"
    assert_includes prompt, "Never mention the score, goalscorers, winner, or result"
  end
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
bin/rails test test/services/upcoming_matches_insight_service_test.rb -n "/never_reveal_results/"
```

Expected: FAIL — neither string is in `build_system_prompt`'s output yet.

- [ ] **Step 3: Add the rule to `build_system_prompt`**

In `app/services/upcoming_matches_insight_service.rb`, in `build_system_prompt`, find:

```ruby
      "- Every match comes with its exact date and kick-off time. Never state or imply a different date or day.",
      "- No bullet points, no markdown, no lists. Just flowing paragraphs.",
```

and insert a new rule between them:

```ruby
      "- Every match comes with its exact date and kick-off time. Never state or imply a different date or day.",
      "- If any matches are listed under MATCHES ALREADY PLAYED, open with one brief sentence acknowledging they've happened and pointing people to the highlights. Never mention the score, goalscorers, winner, or result of these matches under any circumstances.",
      "- No bullet points, no markdown, no lists. Just flowing paragraphs.",
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bin/rails test test/services/upcoming_matches_insight_service_test.rb
```

Expected: all tests pass, including the existing `"system prompt casts John Botson in Danny Dyer's voice without relaxing accuracy"` test (the new rule is additive, doesn't remove any existing rule text).

- [ ] **Step 5: Commit**

```bash
git add app/services/upcoming_matches_insight_service.rb test/services/upcoming_matches_insight_service_test.rb
git commit -m "feat: instruct John Botson never to spoil results of already-played matches"
```

---

## Task 3: Invalidate the cache when the recently-finished set changes

**Files:**
- Modify: `app/services/upcoming_matches_insight_service.rb`
- Test: `test/services/upcoming_matches_insight_service_test.rb`

- [ ] **Step 1: Write the failing test**

Add this test to `test/services/upcoming_matches_insight_service_test.rb`, after the test added in Task 2:

```ruby
  test "cache version changes when a match enters the recently-finished window" do
    version_before = UpcomingMatchesInsightService.new([@tomorrow_match]).send(:cache_version)

    korea   = Team.create!(name: "Korea Republic", flag_url: "https://x.com/kr.svg")
    czechia = Team.create!(name: "Czechia", flag_url: "https://x.com/cz.svg")
    Match.create!(
      home_team: korea, away_team: czechia, stage: "Group Stage", status: "PostEvent",
      match_id: "umis-finished-2", home_score: 1, away_score: 0, winner: "home",
      start_time: Time.zone.local(2026, 6, 10, 2, 0, 0)
    )

    version_after = UpcomingMatchesInsightService.new([@tomorrow_match]).send(:cache_version)

    refute_equal version_before, version_after
  end
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
bin/rails test test/services/upcoming_matches_insight_service_test.rb -n "/recently-finished_window/"
```

Expected: FAIL — `version_before` and `version_after` are currently equal, since `cache_version` doesn't yet factor in `recently_finished_matches`.

- [ ] **Step 3: Update `cache_version`**

In `app/services/upcoming_matches_insight_service.rb`, replace:

```ruby
  def cache_version
    match_ids   = @matches.map(&:match_id).sort.join(",")
    leaderboard = Group.includes(teams: [:home_matches, :away_matches]).order(:id).map { |g| "#{g.id}:#{g.total_points}" }.join("|")
    status      = TournamentContextService.new.tournament_status.to_s
    today       = Time.current.in_time_zone(TIME_ZONE).to_date.iso8601
    Digest::SHA256.hexdigest("#{PERSONA_VERSION}|#{today}|#{match_ids}|#{leaderboard}|#{status}")[0, 16]
  end
```

with:

```ruby
  def cache_version
    match_ids   = @matches.map(&:match_id).sort.join(",")
    recent_ids  = recently_finished_matches.map(&:match_id).sort.join(",")
    leaderboard = Group.includes(teams: [:home_matches, :away_matches]).order(:id).map { |g| "#{g.id}:#{g.total_points}" }.join("|")
    status      = TournamentContextService.new.tournament_status.to_s
    today       = Time.current.in_time_zone(TIME_ZONE).to_date.iso8601
    Digest::SHA256.hexdigest("#{PERSONA_VERSION}|#{today}|#{match_ids}|#{recent_ids}|#{leaderboard}|#{status}")[0, 16]
  end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bin/rails test test/services/upcoming_matches_insight_service_test.rb
```

Expected: all tests pass, including the existing `"cache version is tied to the persona..."` and `"cache version changes when the date changes"` tests (both still construct valid hashes — `recent_ids` is just an empty string in their fixtures).

- [ ] **Step 5: Run the full test suite to confirm nothing else broke**

```bash
bin/rails test
```

Expected: 0 failures, 0 errors.

- [ ] **Step 6: Commit**

```bash
git add app/services/upcoming_matches_insight_service.rb test/services/upcoming_matches_insight_service_test.rb
git commit -m "feat: invalidate upcoming-matches insight cache as recently-finished matches enter/exit the 24h window"
```

---

## Self-Review

**Spec coverage:**
- ✅ `recently_finished_matches` (24h rolling window, `PostEvent` only, direct `Match` query) — Task 1
- ✅ "MATCHES ALREADY PLAYED (DO NOT REVEAL RESULTS)" section with team names/stage/kickoff, no scores/owners — Task 1
- ✅ System prompt no-spoiler rule — Task 2
- ✅ `cache_version` includes recently-finished match IDs — Task 3
- ✅ Section omitted entirely when nothing finished recently (existing behaviour preserved) — Task 1, second test
- ✅ Existing tests continue to pass — Task 3, Step 5 (full suite run)

**Placeholder scan:** None found — all steps include complete code and exact commands.

**Type consistency:** `recently_finished_matches` returns an `Array` of `Match` (via `.to_a`), used identically in `build_user_message` (Task 1) and `cache_version` (Task 3) via `.any?` / `.map(&:match_id)` / `.each`. Method name matches across both call sites.
