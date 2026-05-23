# AI Bot Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a math-first, AI-last forecasting bot that computes exact sweepstake outcomes deterministically and narrates them via Groq (llama-4-scout), with BBC Sport RSS news for context.

**Architecture:** ScenarioEngine (pure Ruby) computes team points, friend score deltas, and rank changes for every match outcome. GroqClient sends pre-computed facts to Groq and returns natural language. Insights appear as panels on the match show page and leaderboard index.

**Tech Stack:** Rails 7.1, Minitest, Groq API (OpenAI-compatible, llama-4-scout), BBC Sport RSS, Net::HTTP, Whenever gem for cron.

---

## Codebase Context

Before starting, read these files to understand existing patterns:
- `app/services/ben_motson_service.rb` — existing AI service pattern
- `app/models/group.rb` — `total_points = teams.sum(&:points) * multiplier`
- `app/controllers/matches_controller.rb` — `assign_points` method (canonical scoring rules)
- `test/services/whatsapp_sender_test.rb` — test patterns (Minitest, `with_env` helper, stub pattern)
- `db/schema.rb` — current table structure

**Key schema facts:**
- `groups` table: has `friend_id`, `multiplier` (float), `score`, `total_points`
- `teams` table: has `points` (integer), `progressed` (boolean)
- `groups_teams` join table links groups to teams
- `matches` table: has `stage`, `status`, `winner`, `home_team_id`, `away_team_id`, `home_points`, `away_points`
- No AI commentary columns exist yet on matches

**Scoring rules (from `assign_points` in MatchesController):**
- Group Stage: 0 points to either team
- Last 16, Quarter-finals, Semi-finals, 3rd Place Final: winner +1 pt
- Final: winner +2 pts, runner-up +1 pt
- Knockout progression (entering knockout stage): +1 pt — already awarded when match first appears as PreEvent

**Test pattern:**
```ruby
require "test_helper"
class MyServiceTest < ActiveSupport::TestCase
  test "description" do
    friend = Friend.create!(name: "Test")
    group = Group.create!(name: "G", multiplier: 2.0, friend: friend)
    team = Team.create!(name: "Brazil", flag_url: "https://x.com/f.svg", points: 3)
    group.teams << team
    # assert...
  end
end
```

---

## Phase 1: ScenarioEngine + TournamentContextService + Static UI

### Task 1: ScenarioEngine — deterministic match outcome calculator

**Files:**
- Create: `app/services/scenario_engine.rb`
- Create: `test/services/scenario_engine_test.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/services/scenario_engine_test.rb`:

```ruby
require "test_helper"

class ScenarioEngineTest < ActiveSupport::TestCase
  def setup
    @lewis  = Friend.create!(name: "Lewis")
    @sarah  = Friend.create!(name: "Sarah")
    @lewis_group = Group.create!(name: "Lewis Group", multiplier: 2.0, friend: @lewis)
    @sarah_group = Group.create!(name: "Sarah Group", multiplier: 3.0, friend: @sarah)
    @brazil = Team.create!(name: "Brazil", flag_url: "https://x.com/b.svg", points: 2, progressed: true)
    @france = Team.create!(name: "France", flag_url: "https://x.com/f.svg", points: 1, progressed: true)
    @lewis_group.teams << @brazil
    @sarah_group.teams << @france
  end

  test "knockout match returns home_win and away_win scenarios only" do
    match = Match.create!(
      home_team: @brazil, away_team: @france,
      stage: "Last 16", status: "PreEvent",
      match_id: "test-1", home_score: 0, away_score: 0
    )
    result = ScenarioEngine.new(match).call
    assert_equal [:home_win, :away_win], result.keys
  end

  test "group stage match returns home_win, draw, and away_win scenarios" do
    match = Match.create!(
      home_team: @brazil, away_team: @france,
      stage: "Group Stage", status: "PreEvent",
      match_id: "test-2", home_score: 0, away_score: 0
    )
    result = ScenarioEngine.new(match).call
    assert_equal [:home_win, :draw, :away_win], result.keys
  end

  test "Last 16 home win awards 1 point to home team" do
    match = Match.create!(
      home_team: @brazil, away_team: @france,
      stage: "Last 16", status: "PreEvent",
      match_id: "test-3", home_score: 0, away_score: 0
    )
    result = ScenarioEngine.new(match).call
    home_win = result[:home_win]
    assert_equal 1, home_win[:team_points].length
    assert_equal "Brazil", home_win[:team_points].first[:team_name]
    assert_equal 1, home_win[:team_points].first[:points_awarded]
    assert_equal "Last 16 win", home_win[:team_points].first[:reason]
  end

  test "Last 16 home win adds delta to Lewis who owns Brazil" do
    match = Match.create!(
      home_team: @brazil, away_team: @france,
      stage: "Last 16", status: "PreEvent",
      match_id: "test-4", home_score: 0, away_score: 0
    )
    result = ScenarioEngine.new(match).call
    home_win = result[:home_win]
    lewis_delta = home_win[:friend_deltas].find { |d| d[:friend] == "Lewis" }
    # Brazil earns +1 pt, Lewis has 2x multiplier → +2 friend score
    assert_equal 2.0, lewis_delta[:delta]
    assert_equal @lewis_group.total_points + 2.0, lewis_delta[:new_total]
  end

  test "Last 16 home win updates rank changes correctly" do
    # Sarah currently leads (france 1pt × 3x = 3, lewis brazil 2pt × 2x = 4)
    # Lewis already leads. If Brazil wins, Lewis gap widens, no rank change.
    match = Match.create!(
      home_team: @brazil, away_team: @france,
      stage: "Last 16", status: "PreEvent",
      match_id: "test-5", home_score: 0, away_score: 0
    )
    result = ScenarioEngine.new(match).call
    home_win = result[:home_win]
    assert_equal "Lewis", home_win[:new_leader]
  end

  test "Final home win awards 2 points to winner and 1 to runner-up" do
    match = Match.create!(
      home_team: @brazil, away_team: @france,
      stage: "Final", status: "PreEvent",
      match_id: "test-6", home_score: 0, away_score: 0
    )
    result = ScenarioEngine.new(match).call
    home_win = result[:home_win]
    brazil_pts = home_win[:team_points].find { |t| t[:team_name] == "Brazil" }
    france_pts = home_win[:team_points].find { |t| t[:team_name] == "France" }
    assert_equal 2, brazil_pts[:points_awarded]
    assert_equal 1, france_pts[:points_awarded]
    assert_equal "Final winner", brazil_pts[:reason]
    assert_equal "Final runner-up", france_pts[:reason]
  end

  test "Group Stage outcomes award zero points" do
    match = Match.create!(
      home_team: @brazil, away_team: @france,
      stage: "Group Stage", status: "PreEvent",
      match_id: "test-7", home_score: 0, away_score: 0
    )
    result = ScenarioEngine.new(match).call
    [:home_win, :draw, :away_win].each do |outcome|
      assert_empty result[outcome][:team_points]
      assert_empty result[outcome][:friend_deltas]
    end
  end

  test "rank changes detected when outcome flips leaderboard position" do
    # Make Sarah lead by giving France more points
    @france.update!(points: 5) # Sarah: 5 × 3 = 15; Lewis: 2 × 2 = 4
    match = Match.create!(
      home_team: @brazil, away_team: @france,
      stage: "Semi-finals", status: "PreEvent",
      match_id: "test-8", home_score: 0, away_score: 0
    )
    result = ScenarioEngine.new(match).call
    home_win = result[:home_win] # Brazil wins → Lewis gets +2
    lewis_rank = home_win[:rank_changes].find { |r| r[:friend] == "Lewis" }
    # Lewis was rank 2, after +2 pts still behind Sarah (15 vs 6), no change
    assert_nil lewis_rank

    # Now make it a Semi-final win that flips: Lewis needs a big multiplier
    # France wins: Sarah gets +3, Lewis unchanged at 4; Sarah at 18, Lewis at 4
    away_win = result[:away_win]
    assert_equal "Sarah", away_win[:new_leader]
  end
end
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
bin/rails test test/services/scenario_engine_test.rb
```
Expected: `NameError: uninitialized constant ScenarioEngine` (or similar)

- [ ] **Step 3: Create ScenarioEngine**

Create `app/services/scenario_engine.rb`:

```ruby
class ScenarioEngine
  KNOCKOUT_STAGES = %w[Last\ 16 Quarter-finals Semi-finals Final 3rd\ Place\ Final].freeze

  def initialize(match)
    @match = match
    @all_groups = Group.includes(:teams, :friend).all
  end

  def call
    outcomes.each_with_object({}) do |outcome, result|
      result[outcome] = compute_scenario(outcome)
    end
  end

  private

  def outcomes
    @match.stage == "Group Stage" ? %i[home_win draw away_win] : %i[home_win away_win]
  end

  def compute_scenario(outcome)
    team_pts   = team_points_for(outcome)
    delta_map  = build_delta_map(team_pts)
    friend_scores = current_friend_scores
    projected     = projected_friend_scores(friend_scores, delta_map)

    {
      team_points:   team_pts,
      friend_deltas: compute_friend_deltas(friend_scores, projected),
      rank_changes:  compute_rank_changes(friend_scores, projected),
      new_leader:    projected.max_by { |fs| fs[:projected_score] }&.dig(:friend_name)
    }
  end

  # Returns array of { team_id:, team_name:, points_awarded:, reason: }
  def team_points_for(outcome)
    stage = @match.stage
    return [] if stage == "Group Stage"

    case stage
    when "Last 16", "Quarter-finals", "Semi-finals", "3rd Place Final"
      case outcome
      when :home_win
        [{ team_id: @match.home_team_id, team_name: @match.home_team.name,
           points_awarded: 1, reason: "#{stage} win" }]
      when :away_win
        [{ team_id: @match.away_team_id, team_name: @match.away_team.name,
           points_awarded: 1, reason: "#{stage} win" }]
      else
        []
      end
    when "Final"
      case outcome
      when :home_win
        [
          { team_id: @match.home_team_id, team_name: @match.home_team.name,
            points_awarded: 2, reason: "Final winner" },
          { team_id: @match.away_team_id, team_name: @match.away_team.name,
            points_awarded: 1, reason: "Final runner-up" }
        ]
      when :away_win
        [
          { team_id: @match.away_team_id, team_name: @match.away_team.name,
            points_awarded: 2, reason: "Final winner" },
          { team_id: @match.home_team_id, team_name: @match.home_team.name,
            points_awarded: 1, reason: "Final runner-up" }
        ]
      else
        []
      end
    else
      []
    end
  end

  # { team_id => additional_points } lookup
  def build_delta_map(team_pts)
    team_pts.each_with_object({}) do |tp, h|
      h[tp[:team_id]] = (h[tp[:team_id]] || 0) + tp[:points_awarded]
    end
  end

  # Current friend scores: [{ friend_name:, group_id:, multiplier:, team_ids:, current_score: }]
  def current_friend_scores
    @all_groups.map do |group|
      {
        friend_name:   group.friend&.name || "No owner",
        group_id:      group.id,
        multiplier:    group.multiplier.to_f,
        team_ids:      group.teams.map(&:id),
        current_score: group.total_points.to_f
      }
    end
  end

  # Returns friend_scores with :projected_score added
  def projected_friend_scores(friend_scores, delta_map)
    friend_scores.map do |fs|
      additional = fs[:team_ids].sum { |tid| (delta_map[tid] || 0) * fs[:multiplier] }
      fs.merge(projected_score: fs[:current_score] + additional)
    end
  end

  def compute_friend_deltas(friend_scores, projected)
    projected.filter_map do |ps|
      delta = ps[:projected_score] - ps[:current_score]
      next if delta.zero?
      { friend: ps[:friend_name], delta: delta, new_total: ps[:projected_score] }
    end
  end

  def compute_rank_changes(friend_scores, projected)
    current_ranked  = friend_scores.sort_by { |fs| -fs[:current_score] }
    projected_ranked = projected.sort_by { |fs| -fs[:projected_score] }

    current_ranked.filter_map.with_index do |fs, i|
      old_rank = i + 1
      new_rank = projected_ranked.index { |pr| pr[:friend_name] == fs[:friend_name] }.to_i + 1
      next if old_rank == new_rank
      { friend: fs[:friend_name], old_rank: old_rank, new_rank: new_rank }
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/services/scenario_engine_test.rb
```
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/scenario_engine.rb test/services/scenario_engine_test.rb
git commit -m "feat: add ScenarioEngine for deterministic sweepstake outcome calculation"
```

---

### Task 2: TournamentContextService — standings assembler

**Files:**
- Create: `app/services/tournament_context_service.rb`
- Create: `test/services/tournament_context_service_test.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/services/tournament_context_service_test.rb`:

```ruby
require "test_helper"

class TournamentContextServiceTest < ActiveSupport::TestCase
  def setup
    @lewis = Friend.create!(name: "Lewis")
    @sarah = Friend.create!(name: "Sarah")
    @lewis_group = Group.create!(name: "Lewis Group", multiplier: 2.0, friend: @lewis)
    @sarah_group = Group.create!(name: "Sarah Group", multiplier: 3.0, friend: @sarah)
    brazil = Team.create!(name: "Brazil", flag_url: "https://x.com/b.svg", points: 3, progressed: true)
    france = Team.create!(name: "France", flag_url: "https://x.com/f.svg", points: 1, progressed: true)
    @lewis_group.teams << brazil
    @sarah_group.teams << france
  end

  test "leaderboard returns friends ranked by score descending" do
    ctx = TournamentContextService.new
    lb = ctx.leaderboard
    assert_equal "Lewis", lb.first[:friend]   # 3 × 2 = 6
    assert_equal "Sarah", lb.last[:friend]    # 1 × 3 = 3
    assert_equal 6.0, lb.first[:score]
    assert_equal 3.0, lb.last[:score]
  end

  test "leaderboard includes rank" do
    ctx = TournamentContextService.new
    lb = ctx.leaderboard
    assert_equal 1, lb.first[:rank]
    assert_equal 2, lb.last[:rank]
  end

  test "leaderboard_text formats standings as readable string" do
    ctx = TournamentContextService.new
    text = ctx.leaderboard_text
    assert_includes text, "1. Lewis"
    assert_includes text, "2. Sarah"
  end

  test "news_items returns empty array when no news exists" do
    ctx = TournamentContextService.new
    assert_equal [], ctx.news_items(limit: 3)
  end
end
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
bin/rails test test/services/tournament_context_service_test.rb
```
Expected: `NameError: uninitialized constant TournamentContextService`

- [ ] **Step 3: Create TournamentContextService**

Create `app/services/tournament_context_service.rb`:

```ruby
class TournamentContextService
  def leaderboard
    groups = Group.includes(:teams, :friend).all
    ranked = groups
      .map { |g| { friend: g.friend&.name || "No owner", score: g.total_points.to_f, multiplier: g.multiplier.to_i } }
      .sort_by { |entry| -entry[:score] }
    ranked.each_with_index { |entry, i| entry[:rank] = i + 1 }
    ranked
  end

  def leaderboard_text
    leaderboard.map { |e| "#{e[:rank]}. #{e[:friend]}: #{e[:score].to_i} points (×#{e[:multiplier]})" }.join("\n")
  end

  # Returns up to `limit` recent NewsItems. Returns [] when NewsItem table doesn't exist yet (Phase 1 safety).
  def news_items(limit: 5)
    return [] unless defined?(NewsItem) && NewsItem.table_exists?
    NewsItem.order(published_at: :desc).limit(limit).map do |item|
      { title: item.title, summary: item.summary, published_at: item.published_at }
    end
  rescue => e
    Rails.logger.warn("TournamentContextService#news_items failed: #{e.message}")
    []
  end

  # Returns top `limit` upcoming PreEvent matches ordered by start_time
  def upcoming_matches(limit: 10)
    Match.includes(:home_team, :away_team)
         .where(status: "PreEvent")
         .where("start_time > ?", Time.current)
         .order(:start_time)
         .limit(limit)
  end

  # Returns the 2-3 upcoming matches with the largest possible rank change for any friend
  def pivotal_matches(count: 3)
    upcoming = upcoming_matches(limit: 10)
    scored = upcoming.map do |match|
      scenarios = ScenarioEngine.new(match).call
      max_rank_change = scenarios.values.flat_map { |s| s[:rank_changes] }.map { |rc| (rc[:old_rank] - rc[:new_rank]).abs }.max || 0
      { match: match, max_rank_change: max_rank_change }
    end
    scored.sort_by { |s| -s[:max_rank_change] }.first(count).map { |s| s[:match] }
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/services/tournament_context_service_test.rb
```
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/tournament_context_service.rb test/services/tournament_context_service_test.rb
git commit -m "feat: add TournamentContextService for standings and pivotal match lookup"
```

---

### Task 3: Match show page — controller + view

**Files:**
- Modify: `app/controllers/matches_controller.rb` (update `show` action)
- Create: `app/views/matches/show.html.erb`

- [ ] **Step 1: Update the matches show action**

In `app/controllers/matches_controller.rb`, replace the existing `show` action:

```ruby
def show
  @match = Match.includes(:home_team, :away_team).find(params[:id])
  if @match.status == "PreEvent"
    @scenarios = ScenarioEngine.new(@match).call
  end
end
```

- [ ] **Step 2: Create the match show view with static scenario output**

Create `app/views/matches/show.html.erb`:

```erb
<div class="max-w-7xl mx-auto w-full">
  <header class="page-header">
    <div class="page-header-container">
      <%= link_to matches_path, class: "page-header-button" do %>
        <span class="material-symbols-outlined text-2xl">arrow_back</span>
      <% end %>
      <h1 class="page-title">Match Preview</h1>
      <div class="w-12"></div>
    </div>
  </header>

  <main class="px-4 md:px-6 lg:px-8 pb-24 md:pb-8 space-y-6 pt-6">

    <!-- Match Header -->
    <div class="bg-surface-light dark:bg-surface-dark rounded-2xl p-6 text-center">
      <p class="text-xs text-text-secondary-light dark:text-text-secondary-dark uppercase tracking-widest mb-3"><%= @match.stage %></p>
      <div class="flex items-center justify-center gap-6">
        <div class="text-center flex-1">
          <% if @match.home_team.flag_url.present? %>
            <%= image_tag @match.home_team.flag_url, class: "w-12 h-12 rounded-full object-cover mx-auto mb-2" %>
          <% end %>
          <p class="font-bold text-text-primary-light dark:text-text-primary-dark"><%= @match.home_team.name %></p>
          <% home_friend = @match.home_team.groups.first&.friend %>
          <p class="text-xs text-text-secondary-light dark:text-text-secondary-dark"><%= home_friend&.name || "No owner" %></p>
        </div>
        <div class="text-center">
          <% if @match.status == "PreEvent" %>
            <p class="text-sm text-text-secondary-light dark:text-text-secondary-dark"><%= @match.start_time&.strftime("%d %b, %H:%M") %></p>
            <p class="text-2xl font-bold text-text-primary-light dark:text-text-primary-dark">vs</p>
          <% else %>
            <p class="text-3xl font-bold text-text-primary-light dark:text-text-primary-dark"><%= @match.home_score %> – <%= @match.away_score %></p>
            <p class="text-xs text-text-secondary-light dark:text-text-secondary-dark"><%= @match.status == "MidEvent" ? "LIVE" : "FT" %></p>
          <% end %>
        </div>
        <div class="text-center flex-1">
          <% if @match.away_team.flag_url.present? %>
            <%= image_tag @match.away_team.flag_url, class: "w-12 h-12 rounded-full object-cover mx-auto mb-2" %>
          <% end %>
          <p class="font-bold text-text-primary-light dark:text-text-primary-dark"><%= @match.away_team.name %></p>
          <% away_friend = @match.away_team.groups.first&.friend %>
          <p class="text-xs text-text-secondary-light dark:text-text-secondary-dark"><%= away_friend&.name || "No owner" %></p>
        </div>
      </div>
    </div>

    <!-- Scenario Insight Panel (PreEvent only) -->
    <% if @scenarios.present? %>
      <section>
        <h2 class="text-lg font-bold text-text-primary-light dark:text-text-primary-dark mb-3">What's at stake</h2>
        <div class="space-y-3">
          <% scenario_labels = { home_win: "#{@match.home_team.name} win", draw: "Draw", away_win: "#{@match.away_team.name} win" } %>
          <% @scenarios.each do |outcome, data| %>
            <div class="bg-surface-light dark:bg-surface-dark rounded-2xl p-4">
              <p class="text-xs font-semibold uppercase tracking-widest text-text-secondary-light dark:text-text-secondary-dark mb-3">
                If <%= scenario_labels[outcome] %>
              </p>
              <% if data[:friend_deltas].any? %>
                <div class="space-y-2 mb-3">
                  <% data[:friend_deltas].each do |delta| %>
                    <div class="flex items-center justify-between">
                      <span class="text-sm text-text-primary-light dark:text-text-primary-dark"><%= delta[:friend] %></span>
                      <span class="text-sm font-bold text-accent-live">+<%= delta[:delta].to_i %> pts → <%= delta[:new_total].to_i %> total</span>
                    </div>
                  <% end %>
                </div>
                <% if data[:rank_changes].any? %>
                  <div class="text-xs text-text-secondary-light dark:text-text-secondary-dark">
                    <% data[:rank_changes].each do |rc| %>
                      <% if rc[:new_rank] < rc[:old_rank] %>
                        <span class="text-accent-live">↑ <%= rc[:friend] %> moves to #<%= rc[:new_rank] %></span>
                      <% else %>
                        <span class="text-red-400">↓ <%= rc[:friend] %> drops to #<%= rc[:new_rank] %></span>
                      <% end %>
                    <% end %>
                  </div>
                <% end %>
                <% if data[:new_leader] %>
                  <p class="text-xs font-semibold text-text-secondary-light dark:text-text-secondary-dark mt-2">
                    Leader: <%= data[:new_leader] %>
                  </p>
                <% end %>
              <% else %>
                <p class="text-sm text-text-secondary-light dark:text-text-secondary-dark">No sweepstake points at stake in this scenario.</p>
              <% end %>
            </div>
          <% end %>
        </div>
      </section>
    <% end %>

  </main>
</div>

<%= render 'layouts/bottom_nav' %>
```

- [ ] **Step 3: Add match links to the index view**

In `app/views/matches/index.html.erb`, find the section where individual match cards are rendered. Add a link wrapping each match card to `match_path(match)`. Look for where matches are displayed (after line 60) and wrap the card with:

```erb
<%= link_to match_path(match), class: "block" do %>
  <!-- existing match card content -->
<% end %>
```

Read the full index view first (`app/views/matches/index.html.erb`) to find the exact match card structure, then add the link.

- [ ] **Step 4: Verify in browser**

Start the server and navigate to a match URL: `bin/rails server` then visit `/matches` and click a match. Confirm:
- The show page renders without errors
- A PreEvent knockout match shows scenario cards (may show "No sweepstake points at stake" for group stage — that's correct)
- The back button returns to `/matches`

- [ ] **Step 5: Commit**

```bash
git add app/controllers/matches_controller.rb app/views/matches/show.html.erb app/views/matches/index.html.erb
git commit -m "feat: add match show page with static scenario insight panel"
```

---

### Task 4: Leaderboard battleground panel — static version

**Files:**
- Modify: `app/controllers/leaderboard_controller.rb` (update `index` action)
- Create: `app/views/leaderboard/_battleground.html.erb`
- Modify: `app/views/leaderboard/index.html.erb`

- [ ] **Step 1: Update the leaderboard index action**

In `app/controllers/leaderboard_controller.rb`, update `index`:

```ruby
def index
  @groups = Group.includes(:teams, :friend).all.sort_by { |group| -group_total_points(group) }
  ctx = TournamentContextService.new
  @pivotal_matches = ctx.pivotal_matches(count: 3)
  @pivotal_scenarios = @pivotal_matches.each_with_object({}) do |match, h|
    h[match.id] = ScenarioEngine.new(match).call
  end
end
```

- [ ] **Step 2: Create the battleground partial**

Create `app/views/leaderboard/_battleground.html.erb`:

```erb
<% if pivotal_matches.any? %>
  <section class="mb-6">
    <h2 class="text-xl font-bold text-text-primary-light dark:text-text-primary-dark mb-3">This Week's Battleground</h2>
    <div class="space-y-4">
      <% pivotal_matches.each do |match| %>
        <% scenarios = pivotal_scenarios[match.id] %>
        <div class="bg-surface-light dark:bg-surface-dark rounded-2xl p-4">
          <p class="text-xs text-text-secondary-light dark:text-text-secondary-dark uppercase tracking-widest mb-2"><%= match.stage %></p>
          <p class="font-bold text-text-primary-light dark:text-text-primary-dark mb-3">
            <%= match.home_team.name %> vs <%= match.away_team.name %>
            <span class="text-xs font-normal text-text-secondary-light dark:text-text-secondary-dark ml-2"><%= match.start_time&.strftime("%d %b, %H:%M") %></span>
          </p>
          <% if scenarios %>
            <div class="space-y-1">
              <% scenario_labels = { home_win: "#{match.home_team.name} win", draw: "Draw", away_win: "#{match.away_team.name} win" } %>
              <% scenarios.each do |outcome, data| %>
                <% next if data[:friend_deltas].empty? %>
                <div class="flex flex-wrap gap-2 text-xs">
                  <span class="text-text-secondary-light dark:text-text-secondary-dark"><%= scenario_labels[outcome] %>:</span>
                  <% data[:friend_deltas].each do |delta| %>
                    <span class="font-semibold text-accent-live"><%= delta[:friend] %> +<%= delta[:delta].to_i %></span>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
  </section>
<% end %>
```

- [ ] **Step 3: Render the battleground partial in the leaderboard index view**

Open `app/views/leaderboard/index.html.erb`. After the `<main class="flex-grow">` opening tag (or equivalent) and before the Groups Grid, add:

```erb
<%= render 'battleground', pivotal_matches: @pivotal_matches, pivotal_scenarios: @pivotal_scenarios %>
```

Read the current leaderboard index view first to find the right insertion point just before the groups grid section.

- [ ] **Step 4: Verify in browser**

Navigate to `/leaderboard`. Confirm the battleground panel appears showing upcoming pivotal matches with scenario summaries.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/leaderboard_controller.rb app/views/leaderboard/_battleground.html.erb app/views/leaderboard/index.html.erb
git commit -m "feat: add battleground panel to leaderboard showing pivotal match scenarios"
```

---

## Phase 2: GroqClient + AI Narration

### Task 5: GroqClient — Groq API wrapper

**Files:**
- Create: `app/services/groq_client.rb`
- Create: `test/services/groq_client_test.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/services/groq_client_test.rb`:

```ruby
require "test_helper"

class GroqClientTest < ActiveSupport::TestCase
  test "returns nil when GROQ_API_KEY is not set" do
    with_env("GROQ_API_KEY" => nil) do
      result = GroqClient.call(system_prompt: "You are helpful", user_message: "hello")
      assert_nil result
    end
  end

  test "calls Groq API and returns response text" do
    response_body = {
      "choices" => [{ "message" => { "content" => "Great commentary!" } }]
    }.to_json
    response_stub = OpenStruct.new(body: response_body)
    response_stub.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }

    with_env("GROQ_API_KEY" => "test-key") do
      Net::HTTP.stub(:new, ->(_host, _port) {
        http = Minitest::Mock.new
        http.expect(:use_ssl=, nil, [true])
        http.expect(:read_timeout=, nil, [15])
        http.expect(:request, response_stub, [Net::HTTP::Post])
        http
      }) do
        result = GroqClient.call(system_prompt: "You are helpful", user_message: "hello")
        assert_equal "Great commentary!", result
      end
    end
  end

  test "returns nil and logs on API failure" do
    bad_response = OpenStruct.new(code: "500", body: "Internal Server Error")
    bad_response.define_singleton_method(:is_a?) { |_| false }

    logged = []
    with_env("GROQ_API_KEY" => "test-key") do
      Net::HTTP.stub(:new, ->(_host, _port) {
        http = Minitest::Mock.new
        http.expect(:use_ssl=, nil, [true])
        http.expect(:read_timeout=, nil, [15])
        http.expect(:request, bad_response, [Net::HTTP::Post])
        http
      }) do
        Rails.logger.stub(:error, ->(msg) { logged << msg }) do
          result = GroqClient.call(system_prompt: "You are helpful", user_message: "hello")
          assert_nil result
        end
      end
    end
    assert logged.any? { |m| m.include?("Groq API") }
  end

  private

  def with_env(vars, &block)
    original = vars.keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    block.call
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/services/groq_client_test.rb
```
Expected: `NameError: uninitialized constant GroqClient`

- [ ] **Step 3: Create GroqClient**

Create `app/services/groq_client.rb`:

```ruby
class GroqClient
  GROQ_API_URL = "https://api.groq.com/openai/v1/chat/completions".freeze
  PRIMARY_MODEL = "meta-llama/llama-4-scout-17b-16e-instruct".freeze
  FALLBACK_MODEL = "llama-3.3-70b-versatile".freeze

  def self.call(system_prompt:, user_message:, max_tokens: 300, model: PRIMARY_MODEL)
    new(system_prompt: system_prompt, user_message: user_message, max_tokens: max_tokens, model: model).call
  end

  def initialize(system_prompt:, user_message:, max_tokens:, model:)
    @system_prompt = system_prompt
    @user_message  = user_message
    @max_tokens    = max_tokens
    @model         = model
  end

  def call
    api_key = ENV["GROQ_API_KEY"]
    return nil unless api_key

    uri = URI(GROQ_API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 15

    request = Net::HTTP::Post.new(uri.path)
    request["Authorization"] = "Bearer #{api_key}"
    request["Content-Type"]  = "application/json"
    request.body = {
      model:      @model,
      max_tokens: @max_tokens,
      messages:   [
        { role: "system", content: @system_prompt },
        { role: "user",   content: @user_message }
      ]
    }.to_json

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error("Groq API error: #{response.code} #{response.body}")
      return try_fallback(api_key)
    end

    JSON.parse(response.body).dig("choices", 0, "message", "content")
  rescue => e
    Rails.logger.error("Groq API call failed: #{e.message}")
    nil
  end

  private

  def try_fallback(api_key)
    return nil if @model == FALLBACK_MODEL
    self.class.call(
      system_prompt: @system_prompt,
      user_message:  @user_message,
      max_tokens:    @max_tokens,
      model:         FALLBACK_MODEL
    )
  end
end
```

- [ ] **Step 4: Add GROQ_API_KEY to credentials**

```bash
bin/rails credentials:edit
```
Add under the existing keys:
```yaml
groq:
  api_key: YOUR_GROQ_API_KEY_HERE
```

Also update `GroqClient` to fall back to credentials if ENV not set:

In `app/services/groq_client.rb`, change the `api_key` line in `call`:
```ruby
api_key = ENV["GROQ_API_KEY"] || Rails.application.credentials.dig(:groq, :api_key)
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bin/rails test test/services/groq_client_test.rb
```
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/services/groq_client.rb test/services/groq_client_test.rb
git commit -m "feat: add GroqClient wrapping Groq API with llama-4-scout primary model"
```

---

### Task 6: MatchInsightService — AI narration for match scenarios

**Files:**
- Create: `app/services/match_insight_service.rb`
- Create: `test/services/match_insight_service_test.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/services/match_insight_service_test.rb`:

```ruby
require "test_helper"

class MatchInsightServiceTest < ActiveSupport::TestCase
  def setup
    @lewis = Friend.create!(name: "Lewis")
    @lewis_group = Group.create!(name: "Lewis Group", multiplier: 2.0, friend: @lewis)
    brazil = Team.create!(name: "Brazil", flag_url: "https://x.com/b.svg", points: 2, progressed: true)
    france = Team.create!(name: "France", flag_url: "https://x.com/f.svg", points: 1, progressed: true)
    @lewis_group.teams << brazil
    @match = Match.create!(
      home_team: brazil, away_team: france,
      stage: "Quarter-finals", status: "PreEvent",
      match_id: "mi-test-1", home_score: 0, away_score: 0
    )
  end

  test "returns fallback text when Groq is unavailable" do
    with_env("GROQ_API_KEY" => nil) do
      result = MatchInsightService.new(@match).call
      assert_kind_of String, result
      assert result.length > 0
    end
  end

  test "returns Groq response when API available" do
    GroqClient.stub(:call, "Brazil win puts Lewis top!") do
      result = MatchInsightService.new(@match).call
      assert_equal "Brazil win puts Lewis top!", result
    end
  end

  test "falls back gracefully when Groq returns nil" do
    GroqClient.stub(:call, nil) do
      result = MatchInsightService.new(@match).call
      assert_kind_of String, result
    end
  end

  private

  def with_env(vars, &block)
    original = vars.keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    block.call
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/services/match_insight_service_test.rb
```
Expected: `NameError: uninitialized constant MatchInsightService`

- [ ] **Step 3: Create MatchInsightService**

Create `app/services/match_insight_service.rb`:

```ruby
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/services/match_insight_service_test.rb
```
Expected: All tests pass.

- [ ] **Step 5: Wire MatchInsightService into the match show controller**

In `app/controllers/matches_controller.rb`, update the show action to generate AI insight:

```ruby
def show
  @match = Match.includes(:home_team, :away_team).find(params[:id])
  if @match.status == "PreEvent"
    @scenarios = ScenarioEngine.new(@match).call
    @match_insight = MatchInsightService.new(@match).call
  end
end
```

- [ ] **Step 6: Add the AI insight to the match show view**

In `app/views/matches/show.html.erb`, add a commentary box between the Match Header and Scenario Insight Panel sections:

```erb
<% if @match_insight.present? %>
  <div class="commentary-box">
    <div class="commentary-header">
      <i class="fas fa-microphone commentary-icon"></i>
      <h3 class="commentary-title">Ben Motson's Preview</h3>
    </div>
    <p class="commentary-text"><%= @match_insight %></p>
  </div>
<% end %>
```

- [ ] **Step 7: Commit**

```bash
git add app/services/match_insight_service.rb test/services/match_insight_service_test.rb app/controllers/matches_controller.rb app/views/matches/show.html.erb
git commit -m "feat: add MatchInsightService with Groq narration for match scenarios"
```

---

### Task 7: Update BenMotsonService to use GroqClient + ScenarioEngine

**Files:**
- Modify: `app/services/ben_motson_service.rb`
- Create: `test/services/ben_motson_service_test.rb`

- [ ] **Step 1: Write tests for the updated BenMotsonService**

Create `test/services/ben_motson_service_test.rb`:

```ruby
require "test_helper"

class BenMotsonServiceTest < ActiveSupport::TestCase
  def setup
    @lewis = Friend.create!(name: "Lewis")
    @sarah = Friend.create!(name: "Sarah")
    @lewis_group = Group.create!(name: "Lewis Group", multiplier: 2.0, friend: @lewis)
    @sarah_group = Group.create!(name: "Sarah Group", multiplier: 3.0, friend: @sarah)
    brazil = Team.create!(name: "Brazil", flag_url: "https://x.com/b.svg", points: 3, progressed: true)
    france = Team.create!(name: "France", flag_url: "https://x.com/f.svg", points: 1, progressed: true)
    @lewis_group.teams << brazil
    @sarah_group.teams << france
    Match.create!(home_team: brazil, away_team: france, stage: "Semi-finals",
                  status: "PreEvent", match_id: "bms-1", home_score: 0, away_score: 0)
  end

  test "leaderboard insight returns string when Groq unavailable" do
    with_env("GROQ_API_KEY" => nil) do
      result = BenMotsonService.new(:leaderboard).generate_insight
      assert_kind_of String, result
      assert result.length > 0
    end
  end

  test "leaderboard insight uses Groq response when available" do
    GroqClient.stub(:call, "Lewis dominates at the top!") do
      result = BenMotsonService.new(:leaderboard).generate_insight
      assert_equal "Lewis dominates at the top!", result
    end
  end

  test "matches insight returns string" do
    match = Match.first
    result = BenMotsonService.new(:matches, { matches: [match], filter_type: "PreEvent" }).generate_insight
    assert_kind_of String, result
  end

  private

  def with_env(vars, &block)
    original = vars.keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    block.call
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
```

- [ ] **Step 2: Run tests to confirm current state**

```bash
bin/rails test test/services/ben_motson_service_test.rb
```

- [ ] **Step 3: Rewrite BenMotsonService to use GroqClient**

Replace `app/services/ben_motson_service.rb` entirely:

```ruby
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
    system_prompt = build_system_prompt
    user_message  = build_user_message
    GroqClient.call(system_prompt: system_prompt, user_message: user_message, max_tokens: 250) || fallback_insight
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
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/services/ben_motson_service_test.rb
```
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/ben_motson_service.rb test/services/ben_motson_service_test.rb
git commit -m "feat: rewrite BenMotsonService to use GroqClient and ScenarioEngine for accurate leaderboard insights"
```

---

## Phase 3: News Context Enrichment

### Task 8: NewsItem model and migration

**Files:**
- Create: `db/migrate/TIMESTAMP_create_news_items.rb`
- Create: `app/models/news_item.rb`
- Create: `test/models/news_item_test.rb`
- Create: `test/fixtures/news_items.yml`

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate migration CreateNewsItems title:string summary:text guid:string:uniq published_at:datetime
```

- [ ] **Step 2: Run the migration**

```bash
bin/rails db:migrate
```

- [ ] **Step 3: Create the NewsItem model**

Create `app/models/news_item.rb`:

```ruby
class NewsItem < ApplicationRecord
  validates :guid, presence: true, uniqueness: true
  validates :title, presence: true

  scope :recent, -> { order(published_at: :desc) }
end
```

- [ ] **Step 4: Create the test fixture**

Create `test/fixtures/news_items.yml`:

```yaml
# Empty - tests create their own data
```

- [ ] **Step 5: Write and run model tests**

Create `test/models/news_item_test.rb`:

```ruby
require "test_helper"

class NewsItemTest < ActiveSupport::TestCase
  test "requires guid" do
    item = NewsItem.new(title: "Test", published_at: Time.current)
    assert_not item.valid?
    assert_includes item.errors[:guid], "can't be blank"
  end

  test "requires title" do
    item = NewsItem.new(guid: "abc-123", published_at: Time.current)
    assert_not item.valid?
    assert_includes item.errors[:title], "can't be blank"
  end

  test "enforces unique guid" do
    NewsItem.create!(guid: "dup-1", title: "First", published_at: 1.hour.ago)
    duplicate = NewsItem.new(guid: "dup-1", title: "Second", published_at: Time.current)
    assert_not duplicate.valid?
  end

  test "recent scope orders by published_at descending" do
    older = NewsItem.create!(guid: "old-1", title: "Old", published_at: 2.days.ago)
    newer = NewsItem.create!(guid: "new-1", title: "New", published_at: 1.hour.ago)
    assert_equal newer, NewsItem.recent.first
  end
end
```

```bash
bin/rails test test/models/news_item_test.rb
```
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/ app/models/news_item.rb test/models/news_item_test.rb test/fixtures/news_items.yml db/schema.rb
git commit -m "feat: add NewsItem model for BBC Sport RSS headline storage"
```

---

### Task 9: BBC RSS fetch rake task + cron schedule

**Files:**
- Create: `lib/tasks/news_feed.rake`
- Create: `test/tasks/news_feed_rake_test.rb`
- Modify: `config/schedule.rb`

- [ ] **Step 1: Write the failing test**

Create `test/tasks/news_feed_rake_test.rb`:

```ruby
require "test_helper"

class NewsFeedRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks
  end

  test "news_feed:fetch creates NewsItems from valid RSS" do
    rss_xml = <<~XML
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <item>
            <title>Brazil star injured ahead of quarter-final</title>
            <description>Key player ruled out with hamstring strain.</description>
            <guid>https://bbc.co.uk/sport/football/1</guid>
            <pubDate>Sat, 23 May 2026 08:00:00 GMT</pubDate>
          </item>
          <item>
            <title>France squad named for semi-final</title>
            <description>Manager names strong XI for the clash.</description>
            <guid>https://bbc.co.uk/sport/football/2</guid>
            <pubDate>Sat, 23 May 2026 07:00:00 GMT</pubDate>
          </item>
        </channel>
      </rss>
    XML

    Net::HTTP.stub(:get_response, OpenStruct.new(body: rss_xml, is_a?: true)) do
      assert_difference "NewsItem.count", 2 do
        Rake::Task["news_feed:fetch"].execute
      end
    end
  end

  test "news_feed:fetch is idempotent — does not duplicate on re-run" do
    existing_guid = "https://bbc.co.uk/sport/football/99"
    NewsItem.create!(guid: existing_guid, title: "Existing", published_at: 1.hour.ago)

    rss_xml = <<~XML
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <item>
            <title>Existing</title>
            <description>Same item.</description>
            <guid>#{existing_guid}</guid>
            <pubDate>Sat, 23 May 2026 07:00:00 GMT</pubDate>
          </item>
        </channel>
      </rss>
    XML

    Net::HTTP.stub(:get_response, OpenStruct.new(body: rss_xml, is_a?: true)) do
      assert_no_difference "NewsItem.count" do
        Rake::Task["news_feed:fetch"].execute
      end
    end
  end
end
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
bin/rails test test/tasks/news_feed_rake_test.rb
```
Expected: Task not found error.

- [ ] **Step 3: Create the rake task**

Create `lib/tasks/news_feed.rake`:

```ruby
require "net/http"
require "rss"

namespace :news_feed do
  desc "Fetch BBC Sport RSS feed and store new headlines in NewsItem table"
  task fetch: :environment do
    url = URI("https://feeds.bbci.co.uk/sport/football/rss.xml")

    response = Net::HTTP.get_response(url)
    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error("NewsFeed fetch failed: #{response.code}")
      next
    end

    feed = RSS::Parser.parse(response.body, false)
    unless feed
      Rails.logger.warn("NewsFeed: could not parse RSS")
      next
    end

    created = 0
    feed.items.each do |item|
      guid = item.guid&.content || item.link
      next unless guid.present?

      NewsItem.find_or_create_by(guid: guid) do |n|
        n.title        = item.title
        n.summary      = item.description
        n.published_at = item.pubDate || Time.current
        created += 1
      end
    end

    Rails.logger.info("NewsFeed: #{created} new items stored (#{feed.items.count} in feed)")
  end
end
```

- [ ] **Step 4: Add cron schedule entries**

In `config/schedule.rb`, add the two daily news fetches:

```ruby
every :day, at: "7:00 am" do
  rake "news_feed:fetch"
end

every :day, at: "10:00 pm" do
  rake "news_feed:fetch"
end
```

The file should now look like:

```ruby
set :output, Rails.root.join("log/cron.log")

every :day, at: "8:00 am" do
  rake "whatsapp:morning_digest"
end

every 15.minutes do
  rake "whatsapp:check_results"
end

every :day, at: "7:00 am" do
  rake "news_feed:fetch"
end

every :day, at: "10:00 pm" do
  rake "news_feed:fetch"
end
```

- [ ] **Step 5: Run tests to verify**

```bash
bin/rails test test/tasks/news_feed_rake_test.rb
```
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/tasks/news_feed.rake test/tasks/news_feed_rake_test.rb config/schedule.rb
git commit -m "feat: add BBC Sport RSS news feed rake task and 7am/10pm cron schedule"
```

---

## Phase 4: Caching

### Task 10: Cache scenario insights on Match records

**Files:**
- Create: `db/migrate/TIMESTAMP_add_scenario_insight_to_matches.rb`
- Modify: `app/controllers/matches_controller.rb`

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate migration AddScenarioInsightToMatches scenario_insight:text scenario_insight_cache_key:string
```

- [ ] **Step 2: Run the migration**

```bash
bin/rails db:migrate
```

- [ ] **Step 3: Add cache logic to MatchInsightService**

In `app/services/match_insight_service.rb`, add a `cached_call` class method and cache key computation:

Add this as the first method after the class definition:

```ruby
def self.cached_call(match)
  service = new(match)
  cache_key = service.send(:compute_cache_key)

  if match.scenario_insight_cache_key == cache_key && match.scenario_insight.present?
    return match.scenario_insight
  end

  insight = service.call
  match.update_columns(scenario_insight: insight, scenario_insight_cache_key: cache_key) if insight
  insight
end
```

Add the private `compute_cache_key` method to `MatchInsightService`:

```ruby
def compute_cache_key
  relevant_groups = Group.includes(:teams, :friend).select do |g|
    g.teams.any? { |t| t.id == @match.home_team_id || t.id == @match.away_team_id }
  end
  state = relevant_groups.map { |g| "#{g.id}:#{g.total_points}" }.sort.join("|")
  Digest::SHA256.hexdigest("#{@match.status}|#{state}")[0, 16]
end
```

- [ ] **Step 4: Update the matches controller to use cached_call**

In `app/controllers/matches_controller.rb`, update the show action:

```ruby
def show
  @match = Match.includes(:home_team, :away_team).find(params[:id])
  if @match.status == "PreEvent"
    @scenarios = ScenarioEngine.new(@match).call
    @match_insight = MatchInsightService.cached_call(@match)
  end
end
```

- [ ] **Step 5: Manually verify caching works**

Start the server, visit a PreEvent match twice. The second load should be faster (served from `scenario_insight` column). Check in rails console:

```ruby
match = Match.where(status: "PreEvent").first
match.scenario_insight         # should be non-nil after first load
match.scenario_insight_cache_key  # should be a 16-char hex string
```

- [ ] **Step 6: Commit**

```bash
git add db/migrate/ db/schema.rb app/services/match_insight_service.rb app/controllers/matches_controller.rb
git commit -m "feat: cache match scenario insights in DB, invalidate on points change"
```

---

### Task 11: AiInsightCache for leaderboard insights

**Files:**
- Create: `db/migrate/TIMESTAMP_create_ai_insight_caches.rb`
- Create: `app/models/ai_insight_cache.rb`
- Create: `test/models/ai_insight_cache_test.rb`
- Create: `test/fixtures/ai_insight_caches.yml`
- Modify: `app/services/ben_motson_service.rb`

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate migration CreateAiInsightCaches key:string:uniq content:text cache_version:string generated_at:datetime
```

- [ ] **Step 2: Run the migration**

```bash
bin/rails db:migrate
```

- [ ] **Step 3: Create the AiInsightCache model**

Create `app/models/ai_insight_cache.rb`:

```ruby
class AiInsightCache < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :content, presence: true

  def self.fetch(key:, version:)
    record = find_by(key: key)
    return record.content if record&.cache_version == version
    nil
  end

  def self.store(key:, version:, content:)
    find_or_initialize_by(key: key).tap do |r|
      r.update!(content: content, cache_version: version, generated_at: Time.current)
    end
  end
end
```

- [ ] **Step 4: Create the fixture and test**

Create `test/fixtures/ai_insight_caches.yml`:

```yaml
# Empty - tests create their own data
```

Create `test/models/ai_insight_cache_test.rb`:

```ruby
require "test_helper"

class AiInsightCacheTest < ActiveSupport::TestCase
  test "fetch returns nil when no record exists" do
    assert_nil AiInsightCache.fetch(key: "leaderboard", version: "abc123")
  end

  test "fetch returns nil when version does not match" do
    AiInsightCache.create!(key: "leaderboard", content: "Old insight", cache_version: "old", generated_at: Time.current)
    assert_nil AiInsightCache.fetch(key: "leaderboard", version: "new")
  end

  test "fetch returns content when version matches" do
    AiInsightCache.create!(key: "leaderboard", content: "Current insight", cache_version: "v1", generated_at: Time.current)
    assert_equal "Current insight", AiInsightCache.fetch(key: "leaderboard", version: "v1")
  end

  test "store creates new record" do
    assert_difference "AiInsightCache.count", 1 do
      AiInsightCache.store(key: "leaderboard", version: "v1", content: "Fresh insight")
    end
  end

  test "store updates existing record" do
    AiInsightCache.create!(key: "leaderboard", content: "Old", cache_version: "v1", generated_at: Time.current)
    assert_no_difference "AiInsightCache.count" do
      AiInsightCache.store(key: "leaderboard", version: "v2", content: "New")
    end
    assert_equal "New", AiInsightCache.find_by(key: "leaderboard").content
  end
end
```

```bash
bin/rails test test/models/ai_insight_cache_test.rb
```
Expected: All tests pass.

- [ ] **Step 5: Wire caching into BenMotsonService leaderboard insight**

In `app/services/ben_motson_service.rb`, update `generate_insight` for the `:leaderboard` context type to use `AiInsightCache`:

```ruby
def generate_insight
  if @context_type == :leaderboard
    version = leaderboard_cache_version
    cached = AiInsightCache.fetch(key: "leaderboard_battleground", version: version)
    return cached if cached
  end

  system_prompt = build_system_prompt
  user_message  = build_user_message
  result = GroqClient.call(system_prompt: system_prompt, user_message: user_message, max_tokens: 250) || fallback_insight

  if @context_type == :leaderboard && result
    AiInsightCache.store(key: "leaderboard_battleground", version: leaderboard_cache_version, content: result)
  end

  result
end
```

Add the private `leaderboard_cache_version` method:

```ruby
def leaderboard_cache_version
  totals = Group.order(:id).pluck(:id, :total_points).map { |id, pts| "#{id}:#{pts}" }.join("|")
  Digest::SHA256.hexdigest(totals)[0, 16]
end
```

- [ ] **Step 6: Commit**

```bash
git add db/migrate/ db/schema.rb app/models/ai_insight_cache.rb test/models/ai_insight_cache_test.rb test/fixtures/ai_insight_caches.yml app/services/ben_motson_service.rb
git commit -m "feat: add AiInsightCache and wire leaderboard insight caching into BenMotsonService"
```

---

## Final Verification

- [ ] **Run the full test suite**

```bash
bin/rails test
```
Expected: All tests pass with 0 failures, 0 errors.

- [ ] **End-to-end smoke test**

1. Start server: `bin/rails server`
2. Visit `/leaderboard` — confirm battleground panel shows upcoming matches with scenario summaries and Ben Motson commentary (or fallback)
3. Visit `/matches` — confirm match list loads
4. Click a PreEvent match — confirm show page renders with scenario cards and AI insight
5. Click a PostEvent match — confirm show page renders without scenario panel

- [ ] **Test the news feed task manually**

```bash
bin/rails news_feed:fetch
```
Expected: Console logs "NewsFeed: N new items stored". Run again — 0 new items (idempotent).

- [ ] **Final commit**

```bash
git add -p  # stage any remaining changes
git commit -m "feat: complete AI bot enhancement — ScenarioEngine, GroqClient, news feed, caching"
```

---

## Self-Review Notes

**Spec coverage check:**
- ✅ ScenarioEngine with three distinct output objects (Task 1)
- ✅ TournamentContextService with standings + news (Tasks 2 + 9)
- ✅ GroqClient with llama-4-scout primary, 70b fallback (Task 5)
- ✅ MatchInsightService with Ben Motson persona and prompt constraints (Task 6)
- ✅ BenMotsonService rewritten with Groq + ScenarioEngine (Task 7)
- ✅ BBC Sport RSS with 7am/10pm schedule and deduplication (Task 9)
- ✅ Match show page with scenario cards (Task 3)
- ✅ Leaderboard battleground panel (Task 4)
- ✅ Match-level insight caching (Task 10)
- ✅ Leaderboard-level caching via AiInsightCache (Task 11)
- ✅ Phased delivery order followed (engine → Groq → news → cache)
- ✅ Fallbacks preserved throughout

**Known constraints:**
- The news relevance filter in `MatchInsightService#relevant_news?` is a simple keyword match — good enough for Phase 3, can be refined later
- `AiCommentaryService` (mid/post-match commentary) is left using Groq implicitly via the `GroqClient` — a separate task could wire it in if needed
