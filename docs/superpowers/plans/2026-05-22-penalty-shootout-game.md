# Penalty Shootout Mini-Game Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a penalty shootout mini-game tab where friends compete for the longest consecutive goal streak, with scores persisted per friend and shown on a shared leaderboard.

**Architecture:** A `GameScore` model stores each completed streak. A `GamesController` serves the page and handles score saves via JSON fetch. A Stimulus controller (`penalty_game_controller`) manages all game state in the browser — the server is only called when a streak ends.

**Tech Stack:** Rails 7.1, Minitest, Stimulus (Hotwire), Tailwind CSS v4, Postgres, Font Awesome icons

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `db/migrate/TIMESTAMP_create_game_scores.rb` | Create | Migration for game_scores table |
| `app/models/game_score.rb` | Create | GameScore model with validations |
| `test/models/game_score_test.rb` | Create | Model unit tests |
| `app/controllers/games_controller.rb` | Create | index, create, scores actions |
| `test/controllers/games_controller_test.rb` | Create | Controller tests |
| `app/views/games/index.html.erb` | Create | Game page: friend picker, game area, leaderboard |
| `app/assets/tailwind/components/game.css` | Create | Game-specific styles |
| `app/assets/tailwind/application.css` | Modify | Import game.css |
| `app/javascript/controllers/penalty_game_controller.js` | Create | Full game state machine |
| `config/routes.rb` | Modify | Add /game routes |
| `app/views/layouts/_bottom_nav.html.erb` | Modify | Add Game tab (mobile + desktop) |

---

## Task 1: Migration and Model

**Files:**
- Create: `db/migrate/TIMESTAMP_create_game_scores.rb`
- Create: `app/models/game_score.rb`
- Create: `test/models/game_score_test.rb`

- [ ] **Step 1: Write the failing model test**

```ruby
# test/models/game_score_test.rb
require "test_helper"

class GameScoreTest < ActiveSupport::TestCase
  setup do
    @friend = Friend.create!(name: "Lewis")
  end

  test "valid with friend and streak" do
    score = GameScore.new(friend: @friend, streak: 5)
    assert score.valid?
  end

  test "invalid without friend" do
    score = GameScore.new(streak: 5)
    assert_not score.valid?
    assert_includes score.errors[:friend], "must exist"
  end

  test "invalid without streak" do
    score = GameScore.new(friend: @friend)
    assert_not score.valid?
    assert_includes score.errors[:streak], "can't be blank"
  end

  test "invalid with negative streak" do
    score = GameScore.new(friend: @friend, streak: -1)
    assert_not score.valid?
    assert_includes score.errors[:streak], "must be greater than or equal to 0"
  end

  test "best_per_friend returns max streak per friend ordered descending" do
    friend2 = Friend.create!(name: "Ben")
    GameScore.create!(friend: @friend, streak: 12)
    GameScore.create!(friend: @friend, streak: 7)   # lower — should not appear
    GameScore.create!(friend: friend2, streak: 9)

    results = GameScore.best_per_friend
    assert_equal 2, results.length
    assert_equal 12, results.first[:best_streak]
    assert_equal @friend.id, results.first[:friend_id]
    assert_equal 9, results.second[:best_streak]
  end

  test "best_per_friend tie-breaks by earliest first_achieved" do
    friend2 = Friend.create!(name: "Aimee")
    GameScore.create!(friend: @friend, streak: 10, created_at: 2.days.ago)
    GameScore.create!(friend: friend2, streak: 10, created_at: 1.day.ago)

    results = GameScore.best_per_friend
    assert_equal @friend.id, results.first[:friend_id]
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
bin/rails test test/models/game_score_test.rb
```

Expected: `NameError: uninitialized constant GameScore` or similar.

- [ ] **Step 3: Generate the migration**

```bash
bin/rails generate migration CreateGameScores friend:references streak:integer
```

- [ ] **Step 4: Edit the generated migration** to add `null: false` constraints

Open the generated file at `db/migrate/TIMESTAMP_create_game_scores.rb` and ensure it reads:

```ruby
class CreateGameScores < ActiveRecord::Migration[7.1]
  def change
    create_table :game_scores do |t|
      t.references :friend, null: false, foreign_key: true
      t.integer :streak, null: false

      t.timestamps
    end
  end
end
```

- [ ] **Step 5: Run the migration**

```bash
bin/rails db:migrate
```

Expected output ends with: `CreateGameScores: migrated`

- [ ] **Step 6: Write the model**

```ruby
# app/models/game_score.rb
class GameScore < ApplicationRecord
  belongs_to :friend

  validates :streak, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Returns best streak per friend, ordered descending, tie-broken by earliest achieved.
  # Each element is a hash with: friend_id, best_streak, first_achieved, friend
  def self.best_per_friend
    joins(:friend)
      .select("friend_id, MAX(streak) AS best_streak, MIN(created_at) AS first_achieved")
      .group(:friend_id)
      .order("best_streak DESC, first_achieved ASC")
      .map do |row|
        {
          friend_id: row.friend_id,
          best_streak: row.best_streak,
          first_achieved: row.first_achieved,
          friend: Friend.find(row.friend_id)
        }
      end
  end
end
```

- [ ] **Step 7: Run tests to confirm they pass**

```bash
bin/rails test test/models/game_score_test.rb
```

Expected: `5 runs, 5 assertions, 0 failures, 0 errors`

- [ ] **Step 8: Commit**

```bash
git add db/migrate/ app/models/game_score.rb test/models/game_score_test.rb db/schema.rb
git commit -m "feat: add GameScore model and migration"
```

---

## Task 2: Routes and Controller

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/games_controller.rb`
- Create: `test/controllers/games_controller_test.rb`

- [ ] **Step 1: Write the failing controller tests**

```ruby
# test/controllers/games_controller_test.rb
require "test_helper"

class GamesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @friend = Friend.create!(name: "Lewis")
  end

  test "GET /game returns 200" do
    get "/game"
    assert_response :success
  end

  test "GET /game/scores returns JSON leaderboard" do
    GameScore.create!(friend: @friend, streak: 7)
    get "/game/scores"
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 1, data.length
    assert_equal 7, data.first["best_streak"]
    assert_equal @friend.id, data.first["friend_id"]
    assert data.first.key?("friend_name")
  end

  test "POST /game/scores saves a score and returns updated leaderboard" do
    assert_difference "GameScore.count", 1 do
      post "/game/scores",
        params: { friend_id: @friend.id, streak: 5 },
        as: :json
    end
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 1, data.length
    assert_equal 5, data.first["best_streak"]
  end

  test "POST /game/scores with invalid friend_id returns 422" do
    post "/game/scores",
      params: { friend_id: 99999, streak: 5 },
      as: :json
    assert_response :unprocessable_entity
  end

  test "POST /game/scores with negative streak returns 422" do
    post "/game/scores",
      params: { friend_id: @friend.id, streak: -1 },
      as: :json
    assert_response :unprocessable_entity
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/controllers/games_controller_test.rb
```

Expected: routing errors (no route matches).

- [ ] **Step 3: Add routes**

Edit `config/routes.rb` — add these three lines inside the `Rails.application.routes.draw do` block:

```ruby
get  '/game',        to: 'games#index'
post '/game/scores', to: 'games#create'
get  '/game/scores', to: 'games#scores'
```

- [ ] **Step 4: Write the controller**

```ruby
# app/controllers/games_controller.rb
class GamesController < ApplicationController
  def index
    @friends = Friend.all.order(:name)
    @leaderboard = leaderboard_data
  end

  def create
    friend = Friend.find_by(id: score_params[:friend_id])

    if friend.nil?
      render json: { error: "Friend not found" }, status: :unprocessable_entity
      return
    end

    score = GameScore.new(friend: friend, streak: score_params[:streak])

    if score.save
      render json: leaderboard_data
    else
      render json: { errors: score.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def scores
    render json: leaderboard_data
  end

  private

  def score_params
    params.permit(:friend_id, :streak)
  end

  def leaderboard_data
    GameScore.best_per_friend.map do |entry|
      {
        friend_id: entry[:friend_id],
        friend_name: entry[:friend].name,
        friend_picture_url: entry[:friend].profile_picture_url,
        best_streak: entry[:best_streak],
        first_achieved: entry[:first_achieved]
      }
    end
  end
end
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
bin/rails test test/controllers/games_controller_test.rb
```

Expected: `5 runs, 8 assertions, 0 failures, 0 errors`

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/games_controller.rb test/controllers/games_controller_test.rb
git commit -m "feat: add GamesController with routes"
```

---

## Task 3: CSS Component

**Files:**
- Create: `app/assets/tailwind/components/game.css`
- Modify: `app/assets/tailwind/application.css`

- [ ] **Step 1: Create the game CSS file**

```css
/* app/assets/tailwind/components/game.css */

/* ── Friend Picker ─────────────────────────────────── */
.game-friend-grid {
  @apply grid grid-cols-3 gap-3 sm:grid-cols-4;
}

.game-friend-btn {
  @apply flex flex-col items-center gap-2 p-3 rounded-xl bg-card-light dark:bg-card-dark
         border-2 border-transparent cursor-pointer transition-all;
}

.game-friend-btn:hover {
  @apply border-primary/50;
}

.game-friend-btn.selected {
  @apply border-primary bg-primary/10;
}

.game-friend-avatar {
  @apply h-12 w-12 rounded-full object-cover;
}

.game-friend-avatar-placeholder {
  @apply h-12 w-12 rounded-full bg-secondary/20 flex items-center justify-center
         text-secondary font-bold text-lg;
}

.game-friend-name {
  @apply text-xs font-semibold text-text-primary-light dark:text-text-primary-dark text-center;
}

/* ── Goal Graphic ──────────────────────────────────── */
.game-goal-wrapper {
  @apply flex flex-col items-center;
}

.game-goal-post {
  @apply relative border-4 border-white mx-auto;
  width: 240px;
  height: 130px;
  border-bottom: none;
  background: rgba(0, 0, 0, 0.35);
  background-image:
    repeating-linear-gradient(90deg, rgba(255,255,255,0.07) 0, rgba(255,255,255,0.07) 1px, transparent 1px, transparent 24px),
    repeating-linear-gradient(180deg, rgba(255,255,255,0.07) 0, rgba(255,255,255,0.07) 1px, transparent 1px, transparent 24px);
}

.game-cursor {
  @apply absolute pointer-events-none;
  width: 16px;
  height: 16px;
  border-radius: 50%;
  background: rgba(255, 255, 0, 0.85);
  box-shadow: 0 0 8px 2px rgba(255, 255, 0, 0.5);
  transform: translate(-50%, -50%);
  top: 50%;
}

.game-keeper {
  @apply absolute bottom-0 left-1/2 -translate-x-1/2 text-5xl leading-none select-none transition-all duration-300;
}

.game-keeper.lean-left  { transform: translateX(-70%) scaleX(-1); }
.game-keeper.lean-right { transform: translateX(10%); }
.game-keeper.dive-left  { transform: translateX(-90%) rotate(-30deg); }
.game-keeper.dive-right { transform: translateX(30%) rotate(30deg); }

.game-ball {
  @apply text-4xl text-center mt-2 select-none;
}

/* ── Streak Counter ────────────────────────────────── */
.game-streak-bar {
  @apply flex items-center justify-between px-4 py-2 rounded-xl bg-card-light dark:bg-card-dark mb-3;
}

.game-streak-counter {
  @apply text-base font-bold text-text-primary-light dark:text-text-primary-dark;
}

.game-pb-label {
  @apply text-sm text-text-secondary-light dark:text-text-secondary-dark;
}

.game-playing-as {
  @apply text-sm font-semibold text-primary;
}

/* ── Bars ──────────────────────────────────────────── */
.game-bar-wrapper {
  @apply mb-3;
}

.game-bar-label {
  @apply text-xs tracking-widest text-text-secondary-light dark:text-text-secondary-dark mb-1;
}

.game-bar-track {
  @apply relative h-4 rounded bg-gray-700 overflow-hidden cursor-pointer;
}

.game-bar-fill {
  @apply absolute left-0 top-0 bottom-0 rounded;
}

.game-bar-fill.direction {
  @apply bg-green-400;
}

.game-bar-fill.power {
  @apply bg-amber-400;
}

.game-bar-cursor {
  @apply absolute top-0 bottom-0 w-1 bg-white rounded;
  box-shadow: 0 0 6px #fff;
}

.game-bar-zones {
  @apply flex justify-between text-gray-500 mt-1;
  font-size: 9px;
}

/* ── Shoot Button ──────────────────────────────────── */
.game-shoot-btn {
  @apply w-full py-3 rounded-xl font-bold text-sm tracking-wide transition-opacity;
  background: #22c55e;
  color: #000;
  border: none;
}

.game-shoot-btn:disabled {
  @apply opacity-40 cursor-not-allowed;
}

.game-hint {
  @apply text-center text-xs text-text-secondary-light dark:text-text-secondary-dark mt-2;
}

/* ── Result Overlay ────────────────────────────────── */
.game-result-overlay {
  @apply absolute inset-0 flex flex-col items-center justify-center rounded-xl z-10;
  background: rgba(0, 0, 0, 0.75);
}

.game-result-text {
  @apply text-4xl font-black mb-4;
}

.game-result-text.goal  { color: #22c55e; }
.game-result-text.saved { color: #ef4444; }

.game-play-again-btn {
  @apply px-6 py-2 rounded-lg font-bold text-sm bg-white text-black cursor-pointer border-none;
}

/* ── Leaderboard ───────────────────────────────────── */
.game-leaderboard-row {
  @apply flex items-center gap-3 px-3 py-2 rounded-xl bg-card-light dark:bg-card-dark;
}

.game-leaderboard-row.new-pb {
  animation: pb-flash 1s ease-out;
}

@keyframes pb-flash {
  0%   { background-color: rgba(34, 197, 94, 0.3); }
  100% { background-color: transparent; }
}

.game-leaderboard-rank {
  @apply w-5 font-bold text-sm text-text-secondary-light dark:text-text-secondary-dark;
}

.game-leaderboard-rank.gold   { color: gold; }
.game-leaderboard-rank.silver { color: silver; }
.game-leaderboard-rank.bronze { color: #cd7f32; }

.game-leaderboard-avatar {
  @apply h-8 w-8 rounded-full object-cover;
}

.game-leaderboard-avatar-placeholder {
  @apply h-8 w-8 rounded-full bg-secondary/20 flex items-center justify-center
         text-xs font-bold text-secondary;
}

.game-leaderboard-name {
  @apply flex-1 font-semibold text-sm text-text-primary-light dark:text-text-primary-dark;
}

.game-leaderboard-streak {
  @apply font-bold text-accent-live text-sm;
}

.game-leaderboard-time {
  @apply text-xs text-text-secondary-light dark:text-text-secondary-dark;
}
```

- [ ] **Step 2: Import game.css in application.css**

Edit `app/assets/tailwind/application.css` — add this line after the existing imports:

```css
@import "./components/game";
```

So the bottom of the file reads:

```css
/* Import component styles */
@import "./components/match-card";
@import "./components/leaderboard";
@import "./components/navigation";
@import "./components/game";
```

- [ ] **Step 3: Rebuild Tailwind to confirm no errors**

```bash
bin/rails tailwindcss:build 2>&1 | tail -5
```

Expected: no errors, ends with something like `Finished in Xms`

- [ ] **Step 4: Commit**

```bash
git add app/assets/tailwind/components/game.css app/assets/tailwind/application.css
git commit -m "feat: add game CSS component"
```

---

## Task 4: Game View

**Files:**
- Create: `app/views/games/index.html.erb`

- [ ] **Step 1: Create the view**

```erb
<%# app/views/games/index.html.erb %>
<div class="max-w-lg mx-auto w-full" data-controller="penalty-game"
     data-penalty-game-friends-value="<%= @friends.to_json(only: [:id, :name, :profile_picture_url]) %>"
     data-penalty-game-leaderboard-value="<%= @leaderboard.to_json %>">

  <header class="page-header">
    <div class="page-header-container">
      <div class="flex w-12 shrink-0 items-center justify-start md:hidden"></div>
      <h1 class="page-title">Penalty Shootout</h1>
      <div class="w-12"></div>
    </div>
  </header>

  <main class="flex-1 px-4 md:px-6 pb-24 md:pb-8 flex flex-col gap-4 pt-4">

    <%# ── Setup: Friend Picker ─────────────────────────── %>
    <div data-penalty-game-target="setupSection">
      <p class="text-sm text-text-secondary-light dark:text-text-secondary-dark mb-3">Who's playing?</p>
      <div class="game-friend-grid" data-penalty-game-target="friendGrid">
        <%# Rendered by Stimulus from friends value %>
      </div>
      <button class="game-shoot-btn mt-4" disabled
              data-penalty-game-target="startBtn"
              data-action="click->penalty-game#startGame">
        Play ⚽
      </button>
    </div>

    <%# ── Playing Area ─────────────────────────────────── %>
    <div data-penalty-game-target="playSection" class="hidden flex flex-col gap-3">

      <%# Streak bar %>
      <div class="game-streak-bar">
        <span class="game-playing-as" data-penalty-game-target="playingAsLabel">Playing as —</span>
        <span class="game-streak-counter" data-penalty-game-target="streakLabel">Streak: 0</span>
        <span class="game-pb-label" data-penalty-game-target="pbLabel">PB: —</span>
      </div>

      <%# Goal graphic %>
      <div class="game-goal-wrapper">
        <div style="background:linear-gradient(180deg,#1a472a 0%,#2d6a4f 60%,#3a7a5a 100%); padding:16px 16px 0; text-align:center; border-radius:12px 12px 0 0;">
          <div class="game-goal-post" data-penalty-game-target="goalPost">
            <div class="game-cursor hidden" data-penalty-game-target="cursor"></div>
            <div class="game-keeper" data-penalty-game-target="keeper">🧤</div>

            <%# Result overlay — hidden until shot resolves %>
            <div class="game-result-overlay hidden" data-penalty-game-target="resultOverlay">
              <div class="game-result-text" data-penalty-game-target="resultText"></div>
              <button class="game-play-again-btn" data-action="click->penalty-game#playAgain">Play Again</button>
            </div>
          </div>
          <div class="game-ball">⚽</div>
        </div>
      </div>

      <%# Controls %>
      <div style="background:#1a1a2e; padding:16px; border-radius:0 0 12px 12px;">

        <%# Direction bar %>
        <div class="game-bar-wrapper" data-penalty-game-target="directionWrapper">
          <div class="game-bar-label">DIRECTION ← →</div>
          <div class="game-bar-track" data-action="click->penalty-game#lockDirection">
            <div class="game-bar-fill direction" data-penalty-game-target="directionFill" style="width:0%"></div>
            <div class="game-bar-cursor" data-penalty-game-target="directionCursor" style="left:0%"></div>
          </div>
          <div class="game-bar-zones"><span>LEFT</span><span>CENTER</span><span>RIGHT</span></div>
        </div>

        <%# Power bar — hidden until direction locked %>
        <div class="game-bar-wrapper hidden" data-penalty-game-target="powerWrapper">
          <div class="game-bar-label">POWER ↑</div>
          <div class="game-bar-track" data-action="click->penalty-game#lockPower">
            <div class="game-bar-fill power" data-penalty-game-target="powerFill" style="width:0%"></div>
            <div class="game-bar-cursor" data-penalty-game-target="powerCursor" style="left:0%"></div>
          </div>
          <div class="game-bar-zones"><span>LOW</span><span>MID</span><span>HIGH</span></div>
        </div>

        <div class="game-hint" data-penalty-game-target="hintText">Tap the direction bar to aim</div>
      </div>

      <button class="text-xs text-text-secondary-light dark:text-text-secondary-dark underline text-center mt-1"
              data-action="click->penalty-game#switchPlayer">Switch player</button>
    </div>

    <%# ── Leaderboard ──────────────────────────────────── %>
    <div class="mt-2">
      <h2 class="text-sm font-bold tracking-widest text-text-secondary-light dark:text-text-secondary-dark mb-2">BEST STREAKS</h2>
      <div class="flex flex-col gap-2" data-penalty-game-target="leaderboard">
        <%# Rendered by Stimulus from leaderboard value %>
      </div>
      <p class="text-center text-xs text-text-secondary-light dark:text-text-secondary-dark mt-3 hidden"
         data-penalty-game-target="emptyLeaderboard">
        No scores yet — be the first!
      </p>
    </div>

  </main>
</div>

<%= render 'layouts/bottom_nav' %>
```

- [ ] **Step 2: Visit /game in the browser and confirm the page loads**

Start the Rails server (`bin/dev`) and open `http://localhost:3000/game`.
The page loads with "Who's playing?" heading and an empty friend grid (Stimulus populates it — handled in Task 5).

- [ ] **Step 3: Commit**

```bash
git add app/views/games/index.html.erb
git commit -m "feat: add game view scaffold"
```

---

## Task 5: Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/penalty_game_controller.js`

**Security note:** All friend names and URLs come from our own Rails backend. They are still escaped via a helper function (`escapeHtml`) before being set as DOM text content, so no raw HTML from server data is ever trusted.

- [ ] **Step 1: Create the Stimulus controller**

```javascript
// app/javascript/controllers/penalty_game_controller.js
import { Controller } from "@hotwired/stimulus"

const DIRECTION_SPEED = 1.2  // % per frame
const POWER_SPEED     = 1.0

const BLUFF_RATES = [
  { upTo: 5,        rate: 0.00 },
  { upTo: 10,       rate: 0.20 },
  { upTo: 15,       rate: 0.40 },
  { upTo: 20,       rate: 0.60 },
  { upTo: Infinity, rate: 0.75 },
]

function bluffRate(streak) {
  return BLUFF_RATES.find(b => streak < b.upTo).rate
}

function zone(pct) {
  if (pct < 33) return "left"
  if (pct < 67) return "center"
  return "right"
}

function timeAgo(isoString) {
  if (!isoString) return ""
  const diff = Math.floor((Date.now() - new Date(isoString)) / 1000)
  if (diff < 60)    return `${diff}s ago`
  if (diff < 3600)  return `${Math.floor(diff / 60)}m ago`
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`
  return `${Math.floor(diff / 86400)}d ago`
}

// Escapes a string for safe insertion into the DOM as text
function escapeHtml(str) {
  const div = document.createElement("div")
  div.appendChild(document.createTextNode(String(str)))
  return div.innerHTML
}

export default class extends Controller {
  static targets = [
    "setupSection", "playSection",
    "friendGrid", "startBtn",
    "playingAsLabel", "streakLabel", "pbLabel",
    "goalPost", "cursor", "keeper", "resultOverlay", "resultText",
    "directionWrapper", "directionFill", "directionCursor",
    "powerWrapper", "powerFill", "powerCursor",
    "hintText", "leaderboard", "emptyLeaderboard"
  ]

  static values = {
    friends:     Array,
    leaderboard: Array,
  }

  connect() {
    this.streak          = 0
    this.selectedFriend  = null
    this.dirPct          = 0
    this.dirDir          = 1
    this.pwrPct          = 0
    this.pwrDir          = 1
    this.dirLocked       = false
    this.directionZone   = null
    this.actualDiveZone  = null
    this.telegraphedZone = null
    this.raf             = null
    this.tapTimeout      = null

    this._renderFriendGrid()
    this._renderLeaderboard(this.leaderboardValue)

    // Restore session
    const saved = sessionStorage.getItem("penalty_game_friend")
    if (saved) {
      const friend = JSON.parse(saved)
      this._selectFriend(friend)
      this._startGame()
    }
  }

  disconnect() {
    cancelAnimationFrame(this.raf)
    clearTimeout(this.tapTimeout)
  }

  // ── Timeout (30s idle = streak lost, no score written) ──

  _startTapTimeout() {
    clearTimeout(this.tapTimeout)
    this.tapTimeout = setTimeout(() => this._onTimeout(), 30000)
  }

  _clearTapTimeout() {
    clearTimeout(this.tapTimeout)
    this.tapTimeout = null
  }

  _onTimeout() {
    cancelAnimationFrame(this.raf)
    this.streak = 0
    this._updateStreakLabel()
    this.resultOverlayTarget.classList.remove("hidden")
    const text     = this.resultTextTarget
    text.textContent = "TIMED OUT ⌛"
    text.className   = "game-result-text saved"
    // No score posted — timeout does not write to DB
  }

  // ── Friend picker ───────────────────────────────────────

  _renderFriendGrid() {
    this.friendGridTarget.replaceChildren()
    this.friendsValue.forEach(f => {
      const btn = document.createElement("button")
      btn.className = "game-friend-btn"
      btn.dataset.action = "click->penalty-game#selectFriend"
      btn.dataset.friend = JSON.stringify(f)

      const avatar = document.createElement("div")
      if (f.profile_picture_url) {
        const img = document.createElement("img")
        img.src = f.profile_picture_url
        img.className = "game-friend-avatar"
        img.alt = f.name
        avatar.appendChild(img)
      } else {
        const placeholder = document.createElement("div")
        placeholder.className = "game-friend-avatar-placeholder"
        placeholder.textContent = f.name[0]
        avatar.appendChild(placeholder)
      }

      const label = document.createElement("span")
      label.className = "game-friend-name"
      label.textContent = f.name

      btn.appendChild(avatar)
      btn.appendChild(label)
      this.friendGridTarget.appendChild(btn)
    })
  }

  selectFriend(event) {
    const btn    = event.currentTarget
    const friend = JSON.parse(btn.dataset.friend)
    this._selectFriend(friend)
    this.friendGridTarget.querySelectorAll(".game-friend-btn").forEach(b => b.classList.remove("selected"))
    btn.classList.add("selected")
  }

  _selectFriend(friend) {
    this.selectedFriend          = friend
    this.startBtnTarget.disabled = false
  }

  startGame() {
    sessionStorage.setItem("penalty_game_friend", JSON.stringify(this.selectedFriend))
    this._startGame()
  }

  _startGame() {
    this.streak = 0
    this._updatePersonalBest()
    this.setupSectionTarget.classList.add("hidden")
    this.playSectionTarget.classList.remove("hidden")
    this.playingAsLabelTarget.textContent = `Playing as ${this.selectedFriend.name}`
    this._startDirectionBar()
  }

  switchPlayer() {
    cancelAnimationFrame(this.raf)
    sessionStorage.removeItem("penalty_game_friend")
    this.selectedFriend = null
    this.streak         = 0
    this.playSectionTarget.classList.add("hidden")
    this.setupSectionTarget.classList.remove("hidden")
    this.startBtnTarget.disabled = true
    this.friendGridTarget.querySelectorAll(".game-friend-btn").forEach(b => b.classList.remove("selected"))
    this._resetBars()
  }

  // ── Direction bar ───────────────────────────────────────

  _startDirectionBar() {
    this.dirLocked = false
    this.dirPct    = 0
    this.dirDir    = 1
    this.cursorTarget.classList.remove("hidden")
    this.directionWrapperTarget.classList.remove("hidden")
    this.powerWrapperTarget.classList.add("hidden")
    this.resultOverlayTarget.classList.add("hidden")
    this.hintTextTarget.textContent = "Tap the direction bar to aim"
    this.keeperTarget.className = "game-keeper"
    this._startTapTimeout()
    this._sweepDirection()
  }

  _sweepDirection() {
    if (this.dirLocked) return
    this.dirPct += DIRECTION_SPEED * this.dirDir
    if (this.dirPct >= 100) { this.dirPct = 100; this.dirDir = -1 }
    if (this.dirPct <= 0)   { this.dirPct = 0;   this.dirDir =  1 }
    this._updateDirectionUI()
    this.raf = requestAnimationFrame(() => this._sweepDirection())
  }

  _updateDirectionUI() {
    const pct     = this.dirPct
    const goalPct = 5 + (pct / 100) * 90   // clamp cursor 5–95% across goal width
    this.directionFillTarget.style.width  = `${pct}%`
    this.directionCursorTarget.style.left = `${pct}%`
    this.cursorTarget.style.left          = `${goalPct}%`
  }

  lockDirection() {
    if (this.dirLocked) return
    this._clearTapTimeout()
    cancelAnimationFrame(this.raf)
    this.dirLocked     = true
    this.directionZone = zone(this.dirPct)
    this._showKeeperTelegraph()
  }

  _showKeeperTelegraph() {
    const rate  = bluffRate(this.streak)
    const bluff = Math.random() < rate
    const zones = ["left", "center", "right"]

    if (bluff) {
      const others        = zones.filter(z => z !== this.directionZone)
      this.actualDiveZone = others[Math.floor(Math.random() * others.length)]
    } else {
      this.actualDiveZone = this.directionZone
    }

    // Telegraph shows actual dive when honest; shows a random wrong zone when bluffing
    if (bluff) {
      const wrongZones        = zones.filter(z => z !== this.actualDiveZone)
      this.telegraphedZone    = wrongZones[Math.floor(Math.random() * wrongZones.length)]
    } else {
      this.telegraphedZone    = this.actualDiveZone
    }

    this.keeperTarget.className = `game-keeper lean-${this.telegraphedZone}`
    setTimeout(() => this._startPowerBar(), 500)
  }

  // ── Power bar ───────────────────────────────────────────

  _startPowerBar() {
    this.pwrPct = 0
    this.pwrDir = 1
    this.powerWrapperTarget.classList.remove("hidden")
    this.hintTextTarget.textContent = "Tap the power bar to shoot!"
    this._startTapTimeout()
    this._sweepPower()
  }

  _sweepPower() {
    this.pwrPct += POWER_SPEED * this.pwrDir
    if (this.pwrPct >= 100) { this.pwrPct = 100; this.pwrDir = -1 }
    if (this.pwrPct <= 0)   { this.pwrPct = 0;   this.pwrDir =  1 }
    this.powerFillTarget.style.width  = `${this.pwrPct}%`
    this.powerCursorTarget.style.left = `${this.pwrPct}%`
    this.raf = requestAnimationFrame(() => this._sweepPower())
  }

  lockPower() {
    this._clearTapTimeout()
    cancelAnimationFrame(this.raf)
    const powerZone = zone(this.pwrPct)
    this._resolveShot(powerZone)
  }

  // ── Shot resolution ─────────────────────────────────────

  _resolveShot(powerZone) {
    // Goal if: keeper dived the wrong way, OR same direction but power too high to save
    const sameZone = this.directionZone === this.actualDiveZone
    const goal     = !sameZone || powerZone === "high"

    this.keeperTarget.className = `game-keeper dive-${this.actualDiveZone}`
    this.cursorTarget.classList.add("hidden")

    setTimeout(() => this._showResult(goal), 300)
  }

  _showResult(goal) {
    this.resultOverlayTarget.classList.remove("hidden")
    const text = this.resultTextTarget
    if (goal) {
      this.streak++
      text.textContent = "GOAL ⚽"
      text.className   = "game-result-text goal"
      this._updateStreakLabel()
    } else {
      text.textContent = "SAVED 🧤"
      text.className   = "game-result-text saved"
      this._saveScore()
    }
  }

  playAgain() {
    const wasSaved = this.resultTextTarget.classList.contains("saved")
    if (wasSaved) {
      // Streak already saved — return to friend picker
      this.playSectionTarget.classList.add("hidden")
      this.setupSectionTarget.classList.remove("hidden")
      this.streak = 0
      this._updateStreakLabel()
    } else {
      this._startDirectionBar()
    }
  }

  // ── Score persistence ───────────────────────────────────

  _saveScore() {
    const streakToSave = this.streak
    this.streak = 0

    const csrfToken = document.querySelector('meta[name="csrf-token"]')
    if (!csrfToken) return

    fetch("/game/scores", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken.content
      },
      body: JSON.stringify({ friend_id: this.selectedFriend.id, streak: streakToSave })
    })
    .then(r => r.ok ? r.json() : Promise.reject())
    .then(data => {
      const prevBest = this._myPersonalBest()
      this._renderLeaderboard(data)
      this.leaderboardValue = data
      if (streakToSave > prevBest) this._flashNewPb()
      this._updatePersonalBest()
    })
    .catch(() => {}) // Silent fail — game still works offline
  }

  // ── Leaderboard rendering ───────────────────────────────

  _renderLeaderboard(data) {
    if (!data || data.length === 0) {
      this.leaderboardTarget.replaceChildren()
      this.emptyLeaderboardTarget.classList.remove("hidden")
      return
    }
    this.emptyLeaderboardTarget.classList.add("hidden")
    this.leaderboardTarget.replaceChildren()

    const rankClasses = ["gold", "silver", "bronze"]

    data.forEach((entry, i) => {
      const row = document.createElement("div")
      row.className = "game-leaderboard-row"
      row.dataset.friendId = entry.friend_id

      // Rank
      const rank = document.createElement("span")
      rank.className = `game-leaderboard-rank ${rankClasses[i] || ""}`
      rank.textContent = i + 1
      row.appendChild(rank)

      // Avatar
      if (entry.friend_picture_url) {
        const img = document.createElement("img")
        img.src = entry.friend_picture_url
        img.className = "game-leaderboard-avatar"
        img.alt = entry.friend_name
        row.appendChild(img)
      } else {
        const placeholder = document.createElement("div")
        placeholder.className = "game-leaderboard-avatar-placeholder"
        placeholder.textContent = entry.friend_name[0]
        row.appendChild(placeholder)
      }

      // Name
      const name = document.createElement("span")
      name.className = "game-leaderboard-name"
      name.textContent = entry.friend_name
      row.appendChild(name)

      // Streak
      const streak = document.createElement("span")
      streak.className = "game-leaderboard-streak"
      streak.textContent = `${entry.best_streak} 🔥`
      row.appendChild(streak)

      // Time
      const time = document.createElement("span")
      time.className = "game-leaderboard-time"
      time.textContent = timeAgo(entry.first_achieved)
      row.appendChild(time)

      this.leaderboardTarget.appendChild(row)
    })
  }

  _flashNewPb() {
    if (!this.selectedFriend) return
    const row = this.leaderboardTarget.querySelector(`[data-friend-id="${this.selectedFriend.id}"]`)
    if (row) {
      row.classList.remove("new-pb")
      void row.offsetWidth // force reflow to restart animation
      row.classList.add("new-pb")
    }
  }

  _myPersonalBest() {
    const entry = (this.leaderboardValue || []).find(e => e.friend_id === this.selectedFriend?.id)
    return entry ? entry.best_streak : 0
  }

  _updatePersonalBest() {
    const pb = this._myPersonalBest()
    this.pbLabelTarget.textContent = pb > 0 ? `PB: ${pb} 🔥` : "PB: —"
  }

  _updateStreakLabel() {
    this.streakLabelTarget.textContent = `Streak: ${this.streak}`
  }

  _resetBars() {
    this.directionFillTarget.style.width  = "0%"
    this.directionCursorTarget.style.left = "0%"
    this.powerFillTarget.style.width      = "0%"
    this.powerCursorTarget.style.left     = "0%"
  }
}
```

- [ ] **Step 2: Rebuild Tailwind and restart dev server**

```bash
bin/rails tailwindcss:build
bin/dev
```

- [ ] **Step 3: Manual smoke test**

Open `http://localhost:3000/game`.

1. Friend grid appears with all friends from the DB.
2. Click a friend — highlighted border appears, Play button enables.
3. Click Play — switches to game area, friend name shown, streak shows 0.
4. Direction bar sweeps left/right, cursor moves inside the goal in sync.
5. Click direction bar — bar freezes, keeper leans left/center/right.
6. After ~0.5s, power bar appears and sweeps.
7. Click power bar — keeper dives, result overlay shows GOAL or SAVED.
8. On GOAL — click Play Again, bars restart, streak increments.
9. On SAVED — click Play Again, returns to friend picker, leaderboard updates.
10. Leaderboard shows friend name, streak, and time.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/penalty_game_controller.js
git commit -m "feat: add penalty game Stimulus controller"
```

---

## Task 6: Navigation

**Files:**
- Modify: `app/views/layouts/_bottom_nav.html.erb`

- [ ] **Step 1: Add the Game tab to mobile bottom nav**

In `app/views/layouts/_bottom_nav.html.erb`, add this inside the `.bottom-nav-container` div, after the Groups link (before the dark mode button):

```erb
<%= link_to '/game', class: "bottom-nav-link #{request.path == '/game' ? 'active' : ''}" do %>
  <i class="fas fa-futbol bottom-nav-icon"></i>
  <span class="bottom-nav-label">Game</span>
<% end %>
```

- [ ] **Step 2: Add the Game tab to desktop top nav**

In the same file, inside the desktop nav's flex items div, after the Groups link:

```erb
<%= link_to '/game', class: "flex items-center gap-2 px-4 py-2 rounded-lg transition-colors #{request.path == '/game' ? 'bg-primary text-white' : 'text-text-secondary-light dark:text-text-secondary-dark hover:bg-gray-100 dark:hover:bg-gray-800'}" do %>
  <i class="fas fa-futbol"></i>
  <span class="font-medium">Game</span>
<% end %>
```

- [ ] **Step 3: Verify nav in browser**

Reload `http://localhost:3000/game` — Game tab is active in the nav. Click another tab and back — active state updates correctly.

- [ ] **Step 4: Run the full test suite**

```bash
bin/rails test
```

Expected: all tests pass, 0 failures, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add app/views/layouts/_bottom_nav.html.erb
git commit -m "feat: add Game tab to navigation"
```

---

## Task 7: End-to-End Smoke Test

Full user journey to confirm everything works together.

- [ ] **Step 1: Complete a full session**

1. Open `http://localhost:3000/game` in a fresh browser tab.
2. Pick a friend, play until you score 3 goals then miss.
3. Confirm leaderboard updates with streak of 3.
4. Click Play Again — returns to friend picker.
5. Pick the same friend and beat the streak.
6. Confirm the leaderboard row flashes green and PB label updates.
7. Open a different browser tab, pick a different friend, play.
8. Confirm both friends appear in leaderboard sorted correctly.

- [ ] **Step 2: Confirm sessionStorage persistence**

1. Pick a friend, score a few goals.
2. Navigate to /matches and back to /game.
3. Confirm you're still mid-game as the same friend (no re-picker shown).

- [ ] **Step 3: Confirm difficulty scaling feels right**

Play until streak reaches 10+. The keeper should become noticeably harder to read (telegraph often wrong). Streaks of 15+ should feel genuinely tense.

- [ ] **Step 4: Run full test suite one final time**

```bash
bin/rails test
```

Expected: all tests pass.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "feat: penalty shootout mini-game complete"
```
