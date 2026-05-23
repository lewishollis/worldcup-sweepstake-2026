# Tournament Simulation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `tournament:simulate` rake task that runs a full World Cup tournament end-to-end with random results, exercises the points/leaderboard/AI pipeline, and prints a summary report.

**Architecture:** A `TournamentSimulation` module in `lib/tournament_simulation.rb` encapsulates all pure simulation logic (standings calculation, points assignment, match creation). The rake task orchestrates the full flow — data reset, 72 group stage matches, 16 knockout matches across 5 stages — then prints a final report with live Ben Motson AI commentary.

**Tech Stack:** Rails rake tasks, ActiveRecord, existing `BenMotsonService`, `TournamentContextService`. No new models, routes, or services.

---

## Tournament Structure

- **Group Stage**: 12 groups × 6 round-robin matches = 72 matches (0 sweepstake points)
- **16 qualifiers**: top team from each of 12 groups + best 4 runners-up (by match points then goal difference)
- **Last 16**: 16 teams → 8 matches → 8 winners (+1 progression, +1 win)
- **Quarter-finals**: 8 teams → 4 matches → 4 winners
- **Semi-finals**: 4 teams → 2 matches → 2 winners + 2 losers
- **3rd Place Final**: 2 SF losers → 1 match
- **Final**: 2 SF winners → 1 match (+2 win, +1 runner-up)
- **Total**: 88 matches

---

## File Map

| Action | Path | Purpose |
|--------|------|---------|
| Create | `lib/tournament_simulation.rb` | Simulation helpers: standings, points, match creation |
| Modify | `lib/tasks/tournament.rake` | Add `tournament:simulate` task |
| Create | `test/tasks/tournament_simulate_test.rb` | Unit + integration tests |

---

## Task 1: `TournamentSimulation.calculate_standings` and `standing_stats`

**Files:**
- Create: `lib/tournament_simulation.rb`
- Create: `test/tasks/tournament_simulate_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/tasks/tournament_simulate_test.rb
require "test_helper"
require "rake"

class TournamentSimulateTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks
  end

  teardown do
    Match.delete_all
    Team.delete_all
    Group.delete_all
    Friend.delete_all
    AiInsightCache.delete_all
    Rake::Task["tournament:simulate"].reenable if Rake::Task.task_defined?("tournament:simulate")
  end

  # ── calculate_standings ──────────────────────────────────────────────────

  test "calculate_standings sorts teams by points" do
    require Rails.root.join("lib", "tournament_simulation")

    t1 = Team.create!(name: "Alpha_#{SecureRandom.hex(4)}")
    t2 = Team.create!(name: "Beta_#{SecureRandom.hex(4)}")
    t3 = Team.create!(name: "Gamma_#{SecureRandom.hex(4)}")
    t4 = Team.create!(name: "Delta_#{SecureRandom.hex(4)}")

    # t1: 3W (9pts), t2: 2W (6pts), t3: 1W (3pts), t4: 0W (0pts)
    matches = [
      Match.create!(home_team: t1, away_team: t2, home_score: 2, away_score: 0, status: "PostEvent", stage: "Group Stage", match_id: "standings-1", start_time: 1.day.ago),
      Match.create!(home_team: t1, away_team: t3, home_score: 1, away_score: 0, status: "PostEvent", stage: "Group Stage", match_id: "standings-2", start_time: 1.day.ago),
      Match.create!(home_team: t1, away_team: t4, home_score: 3, away_score: 0, status: "PostEvent", stage: "Group Stage", match_id: "standings-3", start_time: 1.day.ago),
      Match.create!(home_team: t2, away_team: t3, home_score: 2, away_score: 1, status: "PostEvent", stage: "Group Stage", match_id: "standings-4", start_time: 1.day.ago),
      Match.create!(home_team: t2, away_team: t4, home_score: 1, away_score: 0, status: "PostEvent", stage: "Group Stage", match_id: "standings-5", start_time: 1.day.ago),
      Match.create!(home_team: t3, away_team: t4, home_score: 1, away_score: 0, status: "PostEvent", stage: "Group Stage", match_id: "standings-6", start_time: 1.day.ago)
    ]

    result = TournamentSimulation.calculate_standings([t1, t2, t3, t4], matches)

    assert_equal [t1.id, t2.id, t3.id, t4.id], result.map(&:id)
  end

  test "calculate_standings breaks ties by goal difference" do
    require Rails.root.join("lib", "tournament_simulation")

    t1 = Team.create!(name: "TieA_#{SecureRandom.hex(4)}")
    t2 = Team.create!(name: "TieB_#{SecureRandom.hex(4)}")

    # Both teams: 0 wins, no matches — equal. Then t1 has better GD via a draw with big margin.
    matches = [
      Match.create!(home_team: t1, away_team: t2, home_score: 3, away_score: 3, status: "PostEvent", stage: "Group Stage", match_id: "tie-1", start_time: 1.day.ago)
      # 1pt each, GD both 0 — but we want to test GD tiebreak so set unequal scores in two matches
    ]
    # With one draw each has 1pt and GD 0 — tie. Order stable from sort_by means original order wins.
    # Instead test explicitly: t1 wins 3-0 in one match, t2 wins 1-0 in another (against different opponents)
    t3 = Team.create!(name: "TieC_#{SecureRandom.hex(4)}")
    t4 = Team.create!(name: "TieD_#{SecureRandom.hex(4)}")

    # t1: beats t3 3-0 (3pts, GD+3), t2: beats t4 1-0 (3pts, GD+1) — t1 wins on GD
    matches2 = [
      Match.create!(home_team: t1, away_team: t3, home_score: 3, away_score: 0, status: "PostEvent", stage: "Group Stage", match_id: "gd-1", start_time: 1.day.ago),
      Match.create!(home_team: t2, away_team: t4, home_score: 1, away_score: 0, status: "PostEvent", stage: "Group Stage", match_id: "gd-2", start_time: 1.day.ago),
      Match.create!(home_team: t1, away_team: t2, home_score: 0, away_score: 0, status: "PostEvent", stage: "Group Stage", match_id: "gd-3", start_time: 1.day.ago),
      Match.create!(home_team: t3, away_team: t4, home_score: 0, away_score: 0, status: "PostEvent", stage: "Group Stage", match_id: "gd-4", start_time: 1.day.ago)
    ]

    result = TournamentSimulation.calculate_standings([t1, t2, t3, t4], matches + matches2)
    assert_equal t1.id, result[0].id, "t1 should lead on goal difference"
    assert_equal t2.id, result[1].id, "t2 should be second"
  end

  # ── standing_stats ───────────────────────────────────────────────────────

  test "standing_stats returns correct pts and gd for a team" do
    require Rails.root.join("lib", "tournament_simulation")

    t1 = Team.create!(name: "StatsA_#{SecureRandom.hex(4)}")
    t2 = Team.create!(name: "StatsB_#{SecureRandom.hex(4)}")
    t3 = Team.create!(name: "StatsC_#{SecureRandom.hex(4)}")

    matches = [
      Match.create!(home_team: t1, away_team: t2, home_score: 2, away_score: 1, status: "PostEvent", stage: "Group Stage", match_id: "stats-1", start_time: 1.day.ago),
      Match.create!(home_team: t1, away_team: t3, home_score: 1, away_score: 1, status: "PostEvent", stage: "Group Stage", match_id: "stats-2", start_time: 1.day.ago)
    ]

    stats = TournamentSimulation.standing_stats(t1, matches)

    assert_equal 4, stats[:pts]  # 3 (win) + 1 (draw)
    assert_equal 1, stats[:gd]   # (2-1) + (1-1)
    assert_equal 3, stats[:gf]   # 2 + 1
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```
bin/rails test test/tasks/tournament_simulate_test.rb
```
Expected: `NameError: uninitialized constant TournamentSimulation` or `LoadError`.

- [ ] **Step 3: Create `lib/tournament_simulation.rb` with the two methods**

```ruby
# lib/tournament_simulation.rb
module TournamentSimulation
  # Returns teams sorted by group stage standings: points (3/1/0), then goal
  # difference, then goals scored. Takes AR Match objects from a single group.
  def self.calculate_standings(teams, matches)
    stats = teams.each_with_object({}) do |t, h|
      h[t.id] = { pts: 0, gd: 0, gf: 0 }
    end

    matches.each do |m|
      if m.home_score > m.away_score
        stats[m.home_team_id][:pts] += 3
      elsif m.home_score < m.away_score
        stats[m.away_team_id][:pts] += 3
      else
        stats[m.home_team_id][:pts] += 1
        stats[m.away_team_id][:pts] += 1
      end
      stats[m.home_team_id][:gd] += m.home_score - m.away_score
      stats[m.away_team_id][:gd] += m.away_score - m.home_score
      stats[m.home_team_id][:gf] += m.home_score
      stats[m.away_team_id][:gf] += m.away_score
    end

    teams.sort_by { |t| [-stats[t.id][:pts], -stats[t.id][:gd], -stats[t.id][:gf]] }
  end

  # Returns { pts:, gd:, gf: } for a single team across a list of matches.
  # Used to rank runners-up and third-place finishers across groups.
  def self.standing_stats(team, matches)
    stats = { pts: 0, gd: 0, gf: 0 }
    matches.each do |m|
      next unless [m.home_team_id, m.away_team_id].include?(team.id)
      if m.home_team_id == team.id
        stats[:pts] += m.home_score > m.away_score ? 3 : (m.home_score == m.away_score ? 1 : 0)
        stats[:gd]  += m.home_score - m.away_score
        stats[:gf]  += m.home_score
      else
        stats[:pts] += m.away_score > m.home_score ? 3 : (m.home_score == m.away_score ? 1 : 0)
        stats[:gd]  += m.away_score - m.home_score
        stats[:gf]  += m.away_score
      end
    end
    stats
  end
end
```

- [ ] **Step 4: Run tests to confirm passing**

```
bin/rails test test/tasks/tournament_simulate_test.rb
```
Expected: all standings and stats tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/tournament_simulation.rb test/tasks/tournament_simulate_test.rb
git commit -m "feat: add TournamentSimulation module with standings helpers"
```

---

## Task 2: `TournamentSimulation.assign_simulation_points`

**Files:**
- Modify: `lib/tournament_simulation.rb`
- Modify: `test/tasks/tournament_simulate_test.rb`

- [ ] **Step 1: Add failing tests**

Append to `TournamentSimulateTest` in `test/tasks/tournament_simulate_test.rb`:

```ruby
  # ── assign_simulation_points ─────────────────────────────────────────────

  test "assign_simulation_points awards 0 points for Group Stage" do
    require Rails.root.join("lib", "tournament_simulation")

    friend = Friend.create!(name: "GS_#{SecureRandom.hex(4)}")
    group  = Group.create!(name: "GS_Group_#{SecureRandom.hex(4)}", multiplier: 3, friend: friend)
    home   = Team.create!(name: "GS_Home_#{SecureRandom.hex(4)}")
    away   = Team.create!(name: "GS_Away_#{SecureRandom.hex(4)}")
    group.teams << [home, away]

    match = Match.new(
      home_team: home, away_team: away,
      home_score: 2, away_score: 1, winner: "home",
      status: "PostEvent", stage: "Group Stage",
      start_time: Time.now, match_id: "gs-pts-#{SecureRandom.hex(4)}"
    )

    TournamentSimulation.assign_simulation_points(match)

    assert_equal 0, match.home_points
    assert_equal 0, match.away_points
    assert_equal 0, home.reload.points
    assert_equal 0, away.reload.points
  end

  test "assign_simulation_points awards progression + win point in Last 16" do
    require Rails.root.join("lib", "tournament_simulation")

    friend = Friend.create!(name: "L16_#{SecureRandom.hex(4)}")
    group  = Group.create!(name: "L16_Group_#{SecureRandom.hex(4)}", multiplier: 3, friend: friend)
    home   = Team.create!(name: "L16_Home_#{SecureRandom.hex(4)}")
    away   = Team.create!(name: "L16_Away_#{SecureRandom.hex(4)}")
    group.teams << [home, away]

    match = Match.new(
      home_team: home, away_team: away,
      home_score: 2, away_score: 1, winner: "home",
      status: "PostEvent", stage: "Last 16",
      start_time: Time.now, match_id: "l16-pts-#{SecureRandom.hex(4)}"
    )

    TournamentSimulation.assign_simulation_points(match)

    assert_equal 1, match.home_points
    assert_equal 0, match.away_points
    assert_equal 2, home.reload.points  # +1 progression, +1 win
    assert_equal 1, away.reload.points  # +1 progression, +0 win
    assert home.reload.progressed?
    assert away.reload.progressed?
  end

  test "assign_simulation_points does not double-award progression points" do
    require Rails.root.join("lib", "tournament_simulation")

    friend = Friend.create!(name: "Prog_#{SecureRandom.hex(4)}")
    group  = Group.create!(name: "Prog_Group_#{SecureRandom.hex(4)}", multiplier: 3, friend: friend)
    home   = Team.create!(name: "Prog_Home_#{SecureRandom.hex(4)}", progressed: true, points: 1)
    away   = Team.create!(name: "Prog_Away_#{SecureRandom.hex(4)}", progressed: true, points: 1)
    group.teams << [home, away]

    match = Match.new(
      home_team: home, away_team: away,
      home_score: 1, away_score: 0, winner: "home",
      status: "PostEvent", stage: "Quarter-finals",
      start_time: Time.now, match_id: "prog-pts-#{SecureRandom.hex(4)}"
    )

    TournamentSimulation.assign_simulation_points(match)

    # Already progressed → no extra progression point, just win point for home
    assert_equal 2, home.reload.points  # was 1, +1 win
    assert_equal 1, away.reload.points  # was 1, +0
  end

  test "assign_simulation_points awards 2 to Final winner and 1 to runner-up" do
    require Rails.root.join("lib", "tournament_simulation")

    friend = Friend.create!(name: "Final_#{SecureRandom.hex(4)}")
    group  = Group.create!(name: "Final_Group_#{SecureRandom.hex(4)}", multiplier: 3, friend: friend)
    home   = Team.create!(name: "Final_Home_#{SecureRandom.hex(4)}", progressed: true, points: 3)
    away   = Team.create!(name: "Final_Away_#{SecureRandom.hex(4)}", progressed: true, points: 3)
    group.teams << [home, away]

    match = Match.new(
      home_team: home, away_team: away,
      home_score: 1, away_score: 0, winner: "home",
      status: "PostEvent", stage: "Final",
      start_time: Time.now, match_id: "final-pts-#{SecureRandom.hex(4)}"
    )

    TournamentSimulation.assign_simulation_points(match)

    assert_equal 2, match.home_points
    assert_equal 1, match.away_points
    assert_equal 5, home.reload.points  # was 3, +2
    assert_equal 4, away.reload.points  # was 3, +1
  end
```

- [ ] **Step 2: Run to confirm failure**

```
bin/rails test test/tasks/tournament_simulate_test.rb
```
Expected: `NoMethodError: undefined method 'assign_simulation_points'`.

- [ ] **Step 3: Add `assign_simulation_points` to `lib/tournament_simulation.rb`**

Append inside the `TournamentSimulation` module, after `standing_stats`:

```ruby
  # Assigns sweepstake points to both teams for a simulated match. Modifies
  # match.home_points / away_points in-place and persists updated team points.
  # Also grants +1 progression point to any team appearing in a knockout match
  # for the first time (mirrors MatchesController#assign_points logic).
  def self.assign_simulation_points(match)
    stage = match.stage
    knockout_stages = ["Last 16", "Quarter-finals", "Semi-finals", "Final", "3rd Place Final"]

    if knockout_stages.include?(stage)
      home_team = match.home_team
      unless home_team.progressed?
        home_team.update!(progressed: true, points: home_team.points + 1)
      end

      away_team = match.away_team
      unless away_team.progressed?
        away_team.update!(progressed: true, points: away_team.points + 1)
      end
    end

    case stage
    when "Group Stage"
      match.home_points = 0
      match.away_points = 0
    when "Last 16", "Quarter-finals", "Semi-finals", "3rd Place Final"
      match.home_points = match.winner == "home" ? 1 : 0
      match.away_points = match.winner == "away" ? 1 : 0
    when "Final"
      match.home_points = match.winner == "home" ? 2 : 1
      match.away_points = match.winner == "away" ? 2 : 1
    else
      match.home_points = 0
      match.away_points = 0
    end

    match.home_team.reload.update!(points: match.home_team.points + match.home_points) if match.home_points > 0
    match.away_team.reload.update!(points: match.away_team.points + match.away_points) if match.away_points > 0
  end
```

- [ ] **Step 4: Run tests to confirm passing**

```
bin/rails test test/tasks/tournament_simulate_test.rb
```
Expected: all assign_simulation_points tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/tournament_simulation.rb test/tasks/tournament_simulate_test.rb
git commit -m "feat: add assign_simulation_points to TournamentSimulation module"
```

---

## Task 3: `TournamentSimulation.simulate_knockout_match`

**Files:**
- Modify: `lib/tournament_simulation.rb`
- Modify: `test/tasks/tournament_simulate_test.rb`

- [ ] **Step 1: Add failing test**

Append to `TournamentSimulateTest`:

```ruby
  # ── simulate_knockout_match ──────────────────────────────────────────────

  test "simulate_knockout_match creates a PostEvent match with a winner and awards points" do
    require Rails.root.join("lib", "tournament_simulation")

    friend = Friend.create!(name: "KO_#{SecureRandom.hex(4)}")
    group  = Group.create!(name: "KO_Group_#{SecureRandom.hex(4)}", multiplier: 3, friend: friend)
    home   = Team.create!(name: "KO_Home_#{SecureRandom.hex(4)}")
    away   = Team.create!(name: "KO_Away_#{SecureRandom.hex(4)}")
    group.teams << [home, away]

    match = TournamentSimulation.simulate_knockout_match(home, away, "Quarter-finals", 1, "test-qf")

    assert match.persisted?
    assert_equal "PostEvent", match.status
    assert_equal "Quarter-finals", match.stage
    assert_includes %w[home away], match.winner
    assert match.home_score != match.away_score, "knockout match must have a winner (no draw)"
    total_pts = home.reload.points + away.reload.points
    assert total_pts >= 2, "both teams should have at least progression point each"
  end
```

- [ ] **Step 2: Run to confirm failure**

```
bin/rails test test/tasks/tournament_simulate_test.rb
```
Expected: `NoMethodError: undefined method 'simulate_knockout_match'`.

- [ ] **Step 3: Add `simulate_knockout_match` to `lib/tournament_simulation.rb`**

Append inside the `TournamentSimulation` module:

```ruby
  # Creates and persists a PostEvent knockout match. Randomly picks a winner
  # (no draws in knockout). Scores are set to reflect the winner. Calls
  # assign_simulation_points to award team points. Returns the saved Match.
  def self.simulate_knockout_match(home_team, away_team, stage, idx, id_prefix)
    winner = %w[home away].sample

    if winner == "home"
      home_score = rand(1..3)
      away_score = rand(0..home_score - 1)
    else
      away_score = rand(1..3)
      home_score = rand(0..away_score - 1)
    end

    match = Match.new(
      home_team:   home_team,
      away_team:   away_team,
      home_score:  home_score,
      away_score:  away_score,
      winner:      winner,
      status:      "PostEvent",
      stage:       stage,
      start_time:  Time.now,
      match_id:    "#{id_prefix}-#{idx}",
      result:      winner == "home" ? "W" : "L"
    )

    assign_simulation_points(match)
    match.save!
    match
  end
```

- [ ] **Step 4: Run tests to confirm passing**

```
bin/rails test test/tasks/tournament_simulate_test.rb
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/tournament_simulation.rb test/tasks/tournament_simulate_test.rb
git commit -m "feat: add simulate_knockout_match to TournamentSimulation module"
```

---

## Task 4: Rake task skeleton — guard + data reset

**Files:**
- Modify: `lib/tasks/tournament.rake`

- [ ] **Step 1: Add failing integration test**

Append to `TournamentSimulateTest`:

```ruby
  # ── full integration ─────────────────────────────────────────────────────

  def build_simulation_data
    12.times do |g|
      friend = Friend.create!(name: "SimFriend#{g}_#{SecureRandom.hex(4)}")
      group  = Group.create!(name: "SimGroup#{g}", multiplier: 3, friend: friend)
      4.times do |t|
        team = Team.create!(name: "SimTeam#{g}_#{t}_#{SecureRandom.hex(4)}")
        group.teams << team
      end
    end
  end

  test "simulate task aborts when user types 'no'" do
    build_simulation_data

    STDIN.stub(:gets, "no\n") do
      assert_output(/Cancelled/) do
        Rake::Task["tournament:simulate"].invoke
      end
    end

    assert_equal 0, Match.count
  end
```

- [ ] **Step 2: Run to confirm failure**

```
bin/rails test test/tasks/tournament_simulate_test.rb -n "test_simulate_task_aborts_when_user_types_'no'"
```
Expected: `RuntimeError: Don't know how to build task 'tournament:simulate'`.

- [ ] **Step 3: Add the task skeleton to `lib/tasks/tournament.rake`**

Add inside the existing `namespace :tournament do` block, after the `reset` task:

```ruby
  desc "Simulate a full World Cup tournament end-to-end (resets match data + team points)"
  task simulate: :environment do
    require Rails.root.join("lib", "tournament_simulation")

    if Group.count < 12
      puts "❌ Not enough groups (found #{Group.count}, need 12). Run db:seed first."
      next
    end

    print "\n⚠️  This will reset all match data and team points. Continue? (yes/no): "
    confirmation = STDIN.gets.chomp
    unless confirmation.downcase == "yes"
      puts "❌ Cancelled"
      next
    end

    puts "\n🔄 Resetting data..."
    Match.destroy_all
    Team.update_all(points: 0, progressed: false)
    AiInsightCache.destroy_all
    puts "✅ Reset complete\n"
  end
```

- [ ] **Step 4: Run test to confirm passing**

```
bin/rails test test/tasks/tournament_simulate_test.rb -n "test_simulate_task_aborts_when_user_types_'no'"
```
Expected: passes.

- [ ] **Step 5: Commit**

```bash
git add lib/tasks/tournament.rake
git commit -m "feat: add tournament:simulate rake task skeleton with guard and reset"
```

---

## Task 5: Group stage simulation + qualifier determination

**Files:**
- Modify: `lib/tasks/tournament.rake`

- [ ] **Step 1: Add failing test**

Append to `TournamentSimulateTest`:

```ruby
  test "simulate task creates 72 group stage matches and selects 16 qualifiers" do
    build_simulation_data

    # Capture the qualifiers count by checking match count after group stage
    # We stub BenMotsonService to avoid Groq API calls
    stub_commentary = Minitest::Mock.new
    stub_commentary.expect(:generate_insight, "Test commentary")

    BenMotsonService.stub(:new, stub_commentary) do
      STDIN.stub(:gets, "yes\n") do
        capture_io { Rake::Task["tournament:simulate"].invoke }
      end
    end

    assert_equal 88, Match.count, "Expected 88 total matches (72 group + 16 knockout)"
    assert_equal 72, Match.where(stage: "Group Stage").count
    assert_equal 8,  Match.where(stage: "Last 16").count
    assert_equal 4,  Match.where(stage: "Quarter-finals").count
    assert_equal 2,  Match.where(stage: "Semi-finals").count
    assert_equal 1,  Match.where(stage: "3rd Place Final").count
    assert_equal 1,  Match.where(stage: "Final").count

    stub_commentary.verify
  end
```

- [ ] **Step 2: Run to confirm failure**

```
bin/rails test test/tasks/tournament_simulate_test.rb -n "test_simulate_task_creates_72_group_stage_matches_and_selects_16_qualifiers"
```
Expected: `assert_equal 88, 0` (no matches created yet, task exits after reset).

- [ ] **Step 3: Add group stage simulation to the rake task**

Replace the closing `end` of the `simulate` task body with the following (append after the reset block, before the final `end`):

```ruby
    match_counter = 0
    stats = { group_stage: 0, last_16: 0, quarter_finals: 0, semi_finals: 0, third_place: 0, final: 0 }

    # ── Group Stage ──────────────────────────────────────────────────────────
    puts "⚽ Simulating Group Stage..."
    group_match_data = {}  # group_id => { teams: [], matches: [] }

    Group.includes(:teams).each do |group|
      teams   = group.teams.to_a
      matches = []

      teams.combination(2).each do |home_team, away_team|
        home_score = rand(0..3)
        away_score = rand(0..3)
        winner     = if home_score > away_score then "home" elsif away_score > home_score then "away" end

        match = Match.create!(
          home_team:   home_team,
          away_team:   away_team,
          home_score:  home_score,
          away_score:  away_score,
          winner:      winner,
          status:      "PostEvent",
          stage:       "Group Stage",
          start_time:  Time.now - rand(1..21).days,
          match_id:    "sim-gs-#{match_counter += 1}",
          home_points: 0,
          away_points: 0,
          result:      winner == "home" ? "W" : (winner == "away" ? "L" : "D")
        )
        matches << match
        stats[:group_stage] += 1
      end

      group_match_data[group.id] = { teams: teams, matches: matches }
    end
    puts "  ✅ #{stats[:group_stage]} matches\n"

    # ── Qualifiers: top team per group + best 4 runners-up ───────────────────
    puts "📊 Calculating group standings..."
    group_winners  = []
    runners_up     = []

    group_match_data.each do |_group_id, data|
      sorted = TournamentSimulation.calculate_standings(data[:teams], data[:matches])
      group_winners << sorted[0]
      runners_up   << { team: sorted[1], stats: TournamentSimulation.standing_stats(sorted[1], data[:matches]) }
    end

    best_runners_up = runners_up
      .sort_by { |r| [-r[:stats][:pts], -r[:stats][:gd], -r[:stats][:gf]] }
      .first(4)
      .map { |r| r[:team] }

    qualifiers = (group_winners + best_runners_up).shuffle
    puts "  ✅ #{qualifiers.size} teams qualify\n"
```

- [ ] **Step 4: Run test to confirm still failing (but now with 72 group matches)**

```
bin/rails test test/tasks/tournament_simulate_test.rb -n "test_simulate_task_creates_72_group_stage_matches_and_selects_16_qualifiers"
```
Expected: fails at `assert_equal 88, 72` — group stage works, knockout not yet implemented.

- [ ] **Step 5: Commit progress**

```bash
git add lib/tasks/tournament.rake
git commit -m "feat: implement group stage simulation and qualifier determination"
```

---

## Task 6: Knockout rounds

**Files:**
- Modify: `lib/tasks/tournament.rake`

- [ ] **Step 1: Add the knockout rounds to the rake task**

Append after the `puts "  ✅ #{qualifiers.size} teams qualify\n"` line:

```ruby
    # ── Last 16 ───────────────────────────────────────────────────────────────
    puts "⚔️  Simulating Last 16..."
    last_16_winners = qualifiers.each_slice(2).map do |home, away|
      match = TournamentSimulation.simulate_knockout_match(home, away, "Last 16", match_counter += 1, "sim-l16")
      stats[:last_16] += 1
      match.winner == "home" ? home : away
    end
    puts "  ✅ #{stats[:last_16]} matches\n"

    # ── Quarter-finals ────────────────────────────────────────────────────────
    puts "⚔️  Simulating Quarter-finals..."
    qf_winners = last_16_winners.each_slice(2).map do |home, away|
      match = TournamentSimulation.simulate_knockout_match(home, away, "Quarter-finals", match_counter += 1, "sim-qf")
      stats[:quarter_finals] += 1
      match.winner == "home" ? home : away
    end
    puts "  ✅ #{stats[:quarter_finals]} matches\n"

    # ── Semi-finals ───────────────────────────────────────────────────────────
    puts "⚔️  Simulating Semi-finals..."
    sf_winners = []
    sf_losers  = []
    qf_winners.each_slice(2) do |home, away|
      match = TournamentSimulation.simulate_knockout_match(home, away, "Semi-finals", match_counter += 1, "sim-sf")
      stats[:semi_finals] += 1
      sf_winners << (match.winner == "home" ? home : away)
      sf_losers  << (match.winner == "home" ? away : home)
    end
    puts "  ✅ #{stats[:semi_finals]} matches\n"

    # ── 3rd Place Final ───────────────────────────────────────────────────────
    puts "🥉 Simulating 3rd Place Final..."
    TournamentSimulation.simulate_knockout_match(sf_losers[0], sf_losers[1], "3rd Place Final", match_counter += 1, "sim-3rd")
    stats[:third_place] = 1
    puts "  ✅ 1 match\n"

    # ── Final ─────────────────────────────────────────────────────────────────
    puts "🏆 Simulating Final..."
    final_match = TournamentSimulation.simulate_knockout_match(sf_winners[0], sf_winners[1], "Final", match_counter += 1, "sim-final")
    stats[:final] = 1
    champion       = final_match.winner == "home" ? sf_winners[0] : sf_winners[1]
    champion_owner = champion.groups.first&.friend
    puts "  ✅ 1 match\n"
```

- [ ] **Step 2: Run test to confirm passing**

```
bin/rails test test/tasks/tournament_simulate_test.rb -n "test_simulate_task_creates_72_group_stage_matches_and_selects_16_qualifiers"
```
Expected: passes with 88 total matches.

- [ ] **Step 3: Commit**

```bash
git add lib/tasks/tournament.rake
git commit -m "feat: implement knockout rounds in tournament:simulate task"
```

---

## Task 7: Final report + Ben Motson commentary

**Files:**
- Modify: `lib/tasks/tournament.rake`
- Modify: `test/tasks/tournament_simulate_test.rb`

- [ ] **Step 1: Add report output test**

Append to `TournamentSimulateTest`:

```ruby
  test "simulate task prints leaderboard and champion in report" do
    build_simulation_data

    stub_commentary = Minitest::Mock.new
    stub_commentary.expect(:generate_insight, "Great simulation!")

    output = nil
    BenMotsonService.stub(:new, stub_commentary) do
      STDIN.stub(:gets, "yes\n") do
        output = capture_io { Rake::Task["tournament:simulate"].invoke }.first
      end
    end

    assert_includes output, "SIMULATION COMPLETE"
    assert_includes output, "FINAL LEADERBOARD"
    assert_includes output, "CHAMPION:"
    assert_includes output, "BEN MOTSON SAYS:"
    assert_includes output, "Great simulation!"
    stub_commentary.verify
  end
```

- [ ] **Step 2: Run to confirm failure**

```
bin/rails test test/tasks/tournament_simulate_test.rb -n "test_simulate_task_prints_leaderboard_and_champion_in_report"
```
Expected: fails — report not yet in the task.

- [ ] **Step 3: Append report block to the rake task** (after the Final section, before the outer `end`)

```ruby
    # ── Report ────────────────────────────────────────────────────────────────
    puts "\n" + "=" * 50
    puts "  SIMULATION COMPLETE"
    puts "=" * 50
    puts ""
    puts "Total matches simulated: #{stats.values.sum}"
    puts "  Group Stage:     #{stats[:group_stage]}"
    puts "  Last 16:         #{stats[:last_16]}"
    puts "  Quarter-finals:  #{stats[:quarter_finals]}"
    puts "  Semi-finals:     #{stats[:semi_finals]}"
    puts "  3rd Place Final: #{stats[:third_place]}"
    puts "  Final:           #{stats[:final]}"
    puts ""

    puts "FINAL LEADERBOARD"
    puts "-" * 40
    ranked = Group.includes(:friend, :teams).all.sort_by { |g| -g.total_points }
    ranked.each_with_index do |group, i|
      team_str = group.teams.map { |t| "#{t.name}(#{t.points})" }.join(", ")
      puts "#{i + 1}. #{group.friend&.name.to_s.ljust(12)} — #{group.total_points.to_i}pts  (#{team_str})"
    end
    puts ""

    puts "POINTS BREAKDOWN"
    puts "-" * 40
    ranked.each do |group|
      breakdown = group.teams.map { |t| "#{t.name}(#{t.points})" }.join(" + ")
      raw = group.teams.sum(&:points)
      puts "#{group.friend&.name}: #{breakdown} = #{raw} raw × #{group.multiplier.to_i} = #{group.total_points.to_i}pts"
    end
    puts ""

    puts "CHAMPION: #{champion.name} (owned by #{champion_owner&.name || 'Unowned'})"
    puts ""

    puts "BEN MOTSON SAYS:"
    begin
      context     = TournamentContextService.new
      commentary  = BenMotsonService.new(:leaderboard, { leaderboard: context.leaderboard, pivotal_matches: [] }).generate_insight
      puts commentary
    rescue => e
      puts "[Could not generate commentary: #{e.message}]"
    end
    puts ""
    puts "=" * 50
```

- [ ] **Step 4: Run all simulation tests**

```
bin/rails test test/tasks/tournament_simulate_test.rb
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/tasks/tournament.rake test/tasks/tournament_simulate_test.rb
git commit -m "feat: add final report and Ben Motson commentary to tournament:simulate"
```

---

## Task 8: Full test suite + real DB smoke test

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite to confirm nothing is broken**

```
bin/rails test
```
Expected: 84+ runs, 0 failures, 0 errors.

- [ ] **Step 2: Run a real smoke test against your seeded DB**

```bash
bin/rails db:seed        # if not already seeded
bin/rails tournament:simulate
```

Type `yes` when prompted. Expected output ends with `SIMULATION COMPLETE`, a leaderboard, and Ben Motson commentary.

- [ ] **Step 3: Verify the UI reflects the simulation state**

Start the server and browse to:
- `/matches` — should show all 88 simulated matches
- `/leaderboard` — should show friends ranked by total points

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "chore: tournament simulation complete and verified"
```
