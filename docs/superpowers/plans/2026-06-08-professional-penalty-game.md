# Professional Penalty Game Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the penalty game with a live shot preview, tap/keeper feedback, goal celebrations, and visual polish — all CSS + JS, no audio, no rule changes.

**Architecture:** Four independent layers shipped in order. Layer 1 adds a `ghostBall` DOM element that mirrors the cursor in real time. Layers 2–4 add CSS animations and small JS helpers wired into existing controller lifecycle methods. All new DOM elements are added to `index.html.erb`; their targets are registered in the Stimulus controller.

**Tech Stack:** Stimulus JS, Tailwind CSS, Rails ERB. No new dependencies.

---

## File Structure

| File | Changes |
|---|---|
| `app/views/games/index.html.erb` | Add ghost ball, miss-zone strips, aim-zone labels, power label, net ripple, screen flash divs |
| `app/assets/tailwind/components/game.css` | Ghost ball, miss zones, aim zones, power label, screen flash, net ripple, result slide-up, lock flash, bar pop, keeper dive snap, hint milestone, new PB animation |
| `app/javascript/controllers/penalty_game_controller.js` | New targets; ghost ball sync in `_updateDirectionUI` + `_updateHeightUI`; `_vibrate()`; lock flash; bar pop; `_flashScreen()`; `_triggerNetRipple()`; aim zone show/hide; power label; streak milestone text |

---

### Task 1: Layer 1 — Live Shot Preview

Add a ghost ball ring to the goal that tracks the cursor in real time, showing the player exactly where their shot will land before they fire.

**Files:**
- Modify: `app/views/games/index.html.erb`
- Modify: `app/assets/tailwind/components/game.css`
- Modify: `app/javascript/controllers/penalty_game_controller.js`

- [ ] **Step 1: Add ghost ball and miss-zone strips to ERB**

In `app/views/games/index.html.erb`, inside the `<div class="game-goal-post" ...>` block (after the existing `game-cursor` div), add:

```erb
<div class="game-ghost-ball" data-penalty-game-target="ghostBall"></div>
<div class="game-miss-zone left"></div>
<div class="game-miss-zone right"></div>
```

Full updated goal post div (lines 42–52):
```erb
<div class="game-goal-post" data-penalty-game-target="goalPost">
  <div class="game-cursor hidden" data-penalty-game-target="cursor"></div>
  <div class="game-ghost-ball" data-penalty-game-target="ghostBall"></div>
  <div class="game-miss-zone left"></div>
  <div class="game-miss-zone right"></div>
  <div class="game-ball-mark hidden" data-penalty-game-target="ballMark"></div>
  <div class="game-keeper" data-penalty-game-target="keeper">🧤</div>

  <%# Result overlay — hidden until shot resolves %>
  <div class="game-result-overlay hidden" data-penalty-game-target="resultOverlay">
    <div class="game-result-text" data-penalty-game-target="resultText"></div>
    <button class="game-play-again-btn" data-action="click->penalty-game#playAgain" data-penalty-game-target="playAgainBtn">Play Again</button>
  </div>
</div>
```

- [ ] **Step 2: Add CSS for ghost ball and miss-zone strips**

In `app/assets/tailwind/components/game.css`, after the `.game-cursor` block, add:

```css
.game-ghost-ball {
  @apply absolute pointer-events-none;
  width: 22px;
  height: 22px;
  border-radius: 50%;
  background: rgba(255, 255, 0, 0.12);
  border: 2px dashed rgba(255, 255, 0, 0.45);
  transform: translate(-50%, -50%);
  z-index: 14;
  left: 50%;
  top: 85%;
}

.game-miss-zone {
  @apply absolute top-0 bottom-0 pointer-events-none;
  /* 8% of goal bar = miss edge; goalPct mapping: 5 + (8/100)*90 = 12.2% */
  width: 12.2%;
  background: rgba(239, 68, 68, 0.10);
  z-index: 5;
}

.game-miss-zone.left  { left: 0; }
.game-miss-zone.right { right: 0; }
```

- [ ] **Step 3: Register `ghostBall` in Stimulus targets**

In `app/javascript/controllers/penalty_game_controller.js`, update `static targets`:

```javascript
static targets = [
  "setupSection", "playSection",
  "friendGrid", "startBtn",
  "playingAsLabel", "streakLabel", "pbLabel",
  "goalPost", "cursor", "ghostBall", "ballMark", "keeper", "resultOverlay", "resultText",
  "directionWrapper", "directionFill", "directionCursor",
  "powerWrapper", "powerFill", "powerCursor",
  "hintText", "ballBtn", "playAgainBtn", "leaderboard", "emptyLeaderboard"
]
```

- [ ] **Step 4: Sync ghost ball in `_updateDirectionUI`**

In `_updateDirectionUI`, add ghost ball sync after the cursor lines:

```javascript
_updateDirectionUI() {
  const pct     = this.dirPct
  const goalPct = 5 + (pct / 100) * 90   // clamp cursor 5–95% across goal width
  this.directionFillTarget.style.width  = `${pct}%`
  this.directionCursorTarget.style.left = `${pct}%`
  this.cursorTarget.style.left          = `${goalPct}%`
  this.cursorTarget.style.top           = "85%"
  this.ghostBallTarget.style.left       = `${goalPct}%`
  this.ghostBallTarget.style.top        = "85%"
}
```

- [ ] **Step 5: Sync ghost ball vertically in `_updateHeightUI`**

```javascript
_updateHeightUI(pct) {
  // 0 → 85% (ground), POWER_MISS_EDGE → 0% (crossbar), 100 → -20% (above bar)
  const topPct = pct <= POWER_MISS_EDGE
    ? 85 - (pct / POWER_MISS_EDGE) * 85
    : -((pct - POWER_MISS_EDGE) / (100 - POWER_MISS_EDGE)) * 20
  this.cursorTarget.style.top    = `${topPct}%`
  this.ghostBallTarget.style.top = `${topPct}%`
}
```

- [ ] **Step 6: Reset ghost ball in `_startDirectionBar`**

In `_startDirectionBar`, reset the ghost ball to ground level before starting the sweep. Add the two ghost ball lines after the existing cursor reset:

```javascript
_startDirectionBar() {
  this.dirLocked = false
  this.shotFired = false
  this.dirPct    = 0
  this.dirDir    = 1
  this.cursorTarget.style.top        = "85%"
  this.ghostBallTarget.style.left    = "50%"
  this.ghostBallTarget.style.top     = "85%"
  this.cursorTarget.classList.remove("hidden")
  this.directionWrapperTarget.classList.remove("hidden")
  this.powerWrapperTarget.classList.add("hidden")
  this.resultOverlayTarget.classList.add("hidden")
  this.ballMarkTarget.classList.add("hidden")
  this.hintTextTarget.textContent = "Tap the ball to aim"
  this.keeperTarget.className = "game-keeper"
  this._startTapTimeout()
  this.lastFrameTime = null
  this.raf = requestAnimationFrame((ts) => this._sweepDirection(ts))
}
```

- [ ] **Step 7: Lock ghost ball horizontal position in `_startPowerBar`**

In `_startPowerBar`, set the ghost ball's horizontal position to the locked aim position. Add after `this.pwrDir = 1`:

```javascript
_startPowerBar() {
  this.pwrPct = 0
  this.pwrDir = 1
  // Lock ghost ball to the aim position for the power phase
  const lockedGoalPct = 5 + (this.dirPct / 100) * 90
  this.ghostBallTarget.style.left = `${lockedGoalPct}%`
  this.ghostBallTarget.style.top  = "85%"
  this.powerWrapperTarget.classList.remove("hidden")
  this.hintTextTarget.textContent = "Tap to shoot — stop it before it flies over the bar!"
  this._pickKeeperDiveZone()
  const telegraphZone = Math.random() < bluffRate(this.streak)
    ? KEEPER_ZONES.filter(z => z !== this.actualDiveZone)[Math.floor(Math.random() * 2)]
    : this.actualDiveZone
  this.keeperTarget.className = `game-keeper lean-${telegraphZone}`
  this._startTapTimeout()
  this.lastFrameTime = null
  this.raf = requestAnimationFrame((ts) => this._sweepPower(ts))
}
```

- [ ] **Step 8: Hide ghost ball in `_resolveShot`**

In `_resolveShot`, hide the ghost ball when the shot is fired (before `_placeBallMark`):

```javascript
_resolveShot(power, powerMiss) {
  const missed = this.directionMiss || powerMiss

  this.keeperTarget.className = `game-keeper dive-${this.actualDiveZone}`
  this.cursorTarget.classList.add("hidden")
  this.ghostBallTarget.style.opacity = "0"   // hide ghost ball on shot
  this._placeBallMark()

  if (missed) {
    setTimeout(() => this._showResult("missed"), 450)
    return
  }

  const sameZone = this.directionZone === this.actualDiveZone
  const saved    = sameZone && Math.random() < saveChance(power)
  setTimeout(() => this._showResult(saved ? "saved" : "goal"), 450)
}
```

And restore opacity in `_startDirectionBar` (add alongside the ghost ball reset):

```javascript
this.ghostBallTarget.style.opacity  = "1"
this.ghostBallTarget.style.left     = "50%"
this.ghostBallTarget.style.top      = "85%"
```

- [ ] **Step 9: Verify in browser**

Start the dev server (`bin/dev`). Open the penalty game. Confirm:
1. A dashed yellow ring appears on the goal and sweeps left/right with the direction bar
2. After tapping to lock aim, the ring stays at the locked position and rises as power builds
3. When power exceeds ~92%, the ghost ring exits above the crossbar
4. Ghost ring disappears the moment the ball is fired
5. Ghost ring resets to centre/ground for the next round

- [ ] **Step 10: Commit**

```bash
git add app/views/games/index.html.erb app/assets/tailwind/components/game.css app/javascript/controllers/penalty_game_controller.js
git commit -m "feat: live shot preview — ghost ball ring tracks cursor in real time"
```

---

### Task 2: Layer 2 — Tap Feedback + Keeper Drama

Haptic feedback on every tap, a green flash when aim is locked, a pop animation when the power bar appears, and a snappier keeper dive.

**Files:**
- Modify: `app/assets/tailwind/components/game.css`
- Modify: `app/javascript/controllers/penalty_game_controller.js`

- [ ] **Step 1: Add `_vibrate()` helper to the controller**

Add this private method anywhere before `connect()` — place it after `timeAgo()` and before the `el()` helper:

```javascript
function vibrate(pattern) {
  if ("vibrate" in navigator) navigator.vibrate(pattern)
}
```

This is a module-level function (not a method), matching the style of `bluffRate`, `zone`, etc.

- [ ] **Step 2: Add vibrate calls at key moments**

In `tapBall()`:
```javascript
tapBall() {
  vibrate(30)
  if (!this.dirLocked) {
    this.lockDirection()
  } else {
    this.lockPower()
  }
}
```

In `_showResult()`, in the goal branch:
```javascript
if (result === "goal") {
  vibrate([50, 50, 50])
  this.streak++
  ...
}
```

In `_showResult()`, in the non-goal branch:
```javascript
text.textContent = result === "missed" ? "MISSED ↗" : "SAVED 🧤"
text.className   = `game-result-text ${result}`
vibrate(150)
this.playAgainBtnTarget.classList.remove("hidden")
this._saveScore()
```

- [ ] **Step 3: Add direction-lock flash CSS**

In `app/assets/tailwind/components/game.css`, after `.game-bar-danger` rules, add:

```css
/* Direction bar lock flash */
.game-bar-wrapper.locked-flash .game-bar-track {
  animation: lock-flash 0.25s ease-out forwards;
}

@keyframes lock-flash {
  0%   { background-color: rgba(74, 157, 111, 0.55); }
  100% { background-color: #374151; }
}
```

- [ ] **Step 4: Trigger lock flash in `lockDirection()`**

```javascript
lockDirection() {
  if (this.dirLocked) return
  this._clearTapTimeout()
  cancelAnimationFrame(this.raf)
  this.dirLocked     = true
  this.directionZone = zone(this.dirPct)
  this.directionMiss = isMissDirection(this.dirPct)
  // Flash the direction bar to confirm aim was locked
  this.directionWrapperTarget.classList.add("locked-flash")
  setTimeout(() => this.directionWrapperTarget.classList.remove("locked-flash"), 250)
  this._startPowerBar()
}
```

- [ ] **Step 5: Add power bar pop CSS and keeper dive snap**

In `app/assets/tailwind/components/game.css`:

```css
/* Power bar entrance pop */
.game-bar-wrapper.bar-pop {
  transform-origin: top;
  animation: bar-pop 0.18s cubic-bezier(0.34, 1.56, 0.64, 1);
}

@keyframes bar-pop {
  0%   { transform: scaleY(0); opacity: 0; }
  100% { transform: scaleY(1); opacity: 1; }
}
```

Also update the `.game-keeper` transition to snap faster:

```css
.game-keeper {
  @apply absolute bottom-0 left-1/2 text-5xl leading-none select-none;
  transform: translateX(-50%);
  transition: transform 0.2s cubic-bezier(0.34, 1.56, 0.64, 1);
}
```

(Change `0.35s cubic-bezier(0.22, 1, 0.36, 1)` → `0.2s cubic-bezier(0.34, 1.56, 0.64, 1)`)

- [ ] **Step 6: Trigger power bar pop in `_startPowerBar()`**

Add after `this.powerWrapperTarget.classList.remove("hidden")`:

```javascript
this.powerWrapperTarget.classList.add("bar-pop")
setTimeout(() => this.powerWrapperTarget.classList.remove("bar-pop"), 180)
```

- [ ] **Step 7: Verify in browser**

On a mobile device or with DevTools device emulation:
1. Tap the ball — feel the short buzz (30ms) and see the ball scale down on `:active`
2. Lock aim — direction bar flashes green briefly
3. Power bar appears with a pop scale-up
4. Tap to shoot a miss — feel the long buzz (150ms)
5. Score a goal — feel the double buzz pattern
6. Keeper dive should snap faster and feel committed

- [ ] **Step 8: Commit**

```bash
git add app/assets/tailwind/components/game.css app/javascript/controllers/penalty_game_controller.js
git commit -m "feat: tap haptics, direction-lock flash, power bar pop, keeper dive snap"
```

---

### Task 3: Layer 3 — Goal + Miss Celebrations

Screen flash on result, net ripple on goal, result overlay animates in, streak milestone text.

**Files:**
- Modify: `app/views/games/index.html.erb`
- Modify: `app/assets/tailwind/components/game.css`
- Modify: `app/javascript/controllers/penalty_game_controller.js`

- [ ] **Step 1: Add screen flash and net ripple divs to ERB**

Add the screen flash div just inside the outermost `<div data-controller="penalty-game">`, as the first child:

```erb
<div class="max-w-lg mx-auto w-full" data-controller="penalty-game"
     data-penalty-game-friends-value="<%= @friends.to_json(only: [:id, :name, :profile_picture_url]) %>"
     data-penalty-game-leaderboard-value="<%= @leaderboard.to_json %>">

  <div class="game-screen-flash" data-penalty-game-target="screenFlash"></div>

  <header ...>
```

Add the net ripple div inside `.game-goal-post`, after `.game-miss-zone.right`:

```erb
<div class="game-net-ripple" data-penalty-game-target="netRipple"></div>
```

- [ ] **Step 2: CSS for screen flash**

In `game.css`, after `.game-result-overlay` block:

```css
/* Screen flash overlay */
.game-screen-flash {
  position: fixed;
  inset: 0;
  pointer-events: none;
  z-index: 9998;
  opacity: 0;
}

.game-screen-flash.flash-goal {
  animation: flash-white 0.15s ease-out forwards;
}

.game-screen-flash.flash-missed {
  animation: flash-red 0.12s ease-out forwards;
}

.game-screen-flash.flash-saved {
  animation: flash-dark 0.12s ease-out forwards;
}

@keyframes flash-white { 0% { background: rgba(255,255,255,0.4); opacity:1; } 100% { opacity:0; } }
@keyframes flash-red   { 0% { background: rgba(239,68,68,0.3);   opacity:1; } 100% { opacity:0; } }
@keyframes flash-dark  { 0% { background: rgba(30,30,80,0.25);   opacity:1; } 100% { opacity:0; } }
```

- [ ] **Step 3: CSS for net ripple**

```css
/* Net ripple on goal */
.game-net-ripple {
  position: absolute;
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: rgba(255, 255, 255, 0.5);
  pointer-events: none;
  z-index: 25;
  transform: translate(-50%, -50%) scale(0);
  opacity: 0;
}

.game-net-ripple.rippling {
  animation: net-ripple 0.4s ease-out forwards;
}

@keyframes net-ripple {
  0%   { transform: translate(-50%, -50%) scale(1); opacity: 0.6; }
  100% { transform: translate(-50%, -50%) scale(7); opacity: 0;   }
}
```

- [ ] **Step 4: CSS for result overlay slide-up and hint milestone pulse**

Update the existing `.game-result-overlay` rule to animate in when shown, and add milestone styles:

```css
.game-result-overlay {
  @apply absolute inset-0 flex-col items-center justify-center rounded-xl z-10;
  display: flex;
  background: rgba(0, 0, 0, 0.75);
  animation: result-slide-up 0.2s ease-out;
}

@keyframes result-slide-up {
  from { transform: translateY(20px); opacity: 0; }
  to   { transform: translateY(0);    opacity: 1; }
}

/* Milestone hint pulse */
.game-hint.hint-milestone {
  color: #f59e0b;
  animation: hint-pulse 0.7s ease-in-out infinite alternate;
}

@keyframes hint-pulse {
  from { opacity: 0.7; transform: scale(1);    }
  to   { opacity: 1;   transform: scale(1.06); }
}

/* Milestone result text — larger at streak 10+ */
.game-result-text.milestone {
  font-size: 3.5rem;
}
```

- [ ] **Step 5: Register `screenFlash` and `netRipple` targets, add `_flashScreen()` helper**

In `static targets`, add `"screenFlash"` and `"netRipple"`:

```javascript
static targets = [
  "setupSection", "playSection",
  "friendGrid", "startBtn",
  "playingAsLabel", "streakLabel", "pbLabel",
  "goalPost", "cursor", "ghostBall", "ballMark", "keeper", "resultOverlay", "resultText",
  "screenFlash", "netRipple",
  "directionWrapper", "directionFill", "directionCursor",
  "powerWrapper", "powerFill", "powerCursor",
  "hintText", "ballBtn", "playAgainBtn", "leaderboard", "emptyLeaderboard"
]
```

Add a `_flashScreen(type)` helper (place near other private helpers, e.g. after `_clearTapTimeout`):

```javascript
_flashScreen(type) {
  const flash = this.screenFlashTarget
  flash.classList.remove("flash-goal", "flash-missed", "flash-saved")
  void flash.offsetWidth  // reflow to restart animation
  flash.classList.add(`flash-${type}`)
}
```

- [ ] **Step 6: Call `_flashScreen()` in `_showResult()`**

```javascript
_showResult(result) {
  this._flashScreen(result)
  this.resultOverlayTarget.classList.remove("hidden")
  const text = this.resultTextTarget

  if (result === "goal") {
    vibrate([50, 50, 50])
    this.streak++
    this._updateStreakLabel()
    text.textContent = "GOAL ⚽"
    text.className   = "game-result-text goal"
    this.playAgainBtnTarget.classList.add("hidden")

    if (this.streak >= 10) {
      this.hintTextTarget.textContent = "Unstoppable! 🔥🔥🔥"
      this.hintTextTarget.classList.add("hint-milestone")
      text.classList.add("milestone")
    } else if (this.streak >= 5) {
      this.hintTextTarget.textContent = "On fire! 🔥🔥"
      this.hintTextTarget.classList.add("hint-milestone")
      text.classList.remove("milestone")
    } else if (this.streak >= 3) {
      this.hintTextTarget.textContent = `${this.streak} in a row! 🔥`
      this.hintTextTarget.classList.remove("hint-milestone")
      text.classList.remove("milestone")
    } else {
      this.hintTextTarget.textContent = "Next up…"
      this.hintTextTarget.classList.remove("hint-milestone")
      text.classList.remove("milestone")
    }

    setTimeout(() => this._startDirectionBar(), 1200)
    return
  }

  text.textContent = result === "missed" ? "MISSED ↗" : "SAVED 🧤"
  text.className   = `game-result-text ${result}`
  vibrate(150)
  this.playAgainBtnTarget.classList.remove("hidden")
  this._saveScore()
}
```

Also clear `hint-milestone` and `milestone` in `_startDirectionBar()`:

```javascript
this.hintTextTarget.classList.remove("hint-milestone")
this.hintTextTarget.textContent = "Tap the ball to aim"
this.resultTextTarget.classList.remove("milestone")
```

- [ ] **Step 7: Add `_triggerNetRipple()` and call it in `_resolveShot()`**

Add helper method:

```javascript
_triggerNetRipple(left, top) {
  const ripple = this.netRippleTarget
  ripple.style.left = left
  ripple.style.top  = top
  ripple.classList.remove("rippling")
  void ripple.offsetWidth  // reflow to restart animation
  ripple.classList.add("rippling")
}
```

In `_resolveShot()`, call it for non-miss shots. The ball mark's final position is calculated inside `_placeBallMark()` but we need to call the ripple after the ball mark is placed. Refactor `_resolveShot()` to capture the ball position and trigger the ripple only for goals/saves:

```javascript
_resolveShot(power, powerMiss) {
  const missed = this.directionMiss || powerMiss

  this.keeperTarget.className = `game-keeper dive-${this.actualDiveZone}`
  this.cursorTarget.classList.add("hidden")
  this.ghostBallTarget.style.opacity = "0"
  this._placeBallMark()

  // Trigger net ripple for on-target shots (direction not wide, power not over bar)
  if (!missed) {
    const finalLeft = `${this.dirPct}%`
    const finalTop  = `${Math.round(82 - this.pwrPct * 0.77)}%`
    setTimeout(() => this._triggerNetRipple(finalLeft, finalTop), 350)  // after ball lands
  }

  if (missed) {
    setTimeout(() => this._showResult("missed"), 450)
    return
  }

  const sameZone = this.directionZone === this.actualDiveZone
  const saved    = sameZone && Math.random() < saveChance(power)
  setTimeout(() => this._showResult(saved ? "saved" : "goal"), 450)
}
```

- [ ] **Step 8: Verify in browser**

1. Score a goal — white screen flash, net ripple expands from ball landing position, result overlay slides up from below
2. Miss wide — red screen flash, no net ripple
3. Get saved — dark flash, no net ripple (keeper saved it before it hit the net)
4. Build a streak of 3, 5, 10 — hint text scales up and pulses amber at 5+

- [ ] **Step 9: Commit**

```bash
git add app/views/games/index.html.erb app/assets/tailwind/components/game.css app/javascript/controllers/penalty_game_controller.js
git commit -m "feat: screen flash, net ripple, result slide-up, streak milestone pulse"
```

---

### Task 4: Layer 4 — Visual Polish

Aim zone labels on the goal, power level label after shot, enhanced new-PB animation.

**Files:**
- Modify: `app/views/games/index.html.erb`
- Modify: `app/assets/tailwind/components/game.css`
- Modify: `app/javascript/controllers/penalty_game_controller.js`

- [ ] **Step 1: Add aim zone labels and power label to ERB**

Inside `.game-goal-post`, after `.game-miss-zone.right`:

```erb
<%# Aim zone labels — shown during direction phase only %>
<div class="game-aim-zones" data-penalty-game-target="aimZones">
  <span>LEFT</span>
  <span>CENTRE</span>
  <span>RIGHT</span>
</div>

<%# Power level label — shown briefly after shot fires %>
<div class="game-power-label" data-penalty-game-target="powerLabel"></div>
```

- [ ] **Step 2: CSS for aim zones, power label, and enhanced PB animation**

In `game.css`:

```css
/* Aim zone labels */
.game-aim-zones {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: flex-end;
  justify-content: space-around;
  padding-bottom: 5px;
  pointer-events: none;
  z-index: 6;
  opacity: 0;
  transition: opacity 0.2s ease-in;
}

.game-aim-zones.visible {
  opacity: 1;
}

.game-aim-zones span {
  font-size: 8px;
  color: rgba(255, 255, 255, 0.3);
  letter-spacing: 0.08em;
  font-weight: 700;
  text-transform: uppercase;
}

/* Power level label */
.game-power-label {
  position: absolute;
  transform: translateX(-50%);
  bottom: 6px;
  font-size: 9px;
  font-weight: 800;
  letter-spacing: 0.12em;
  color: rgba(255, 255, 255, 0.65);
  pointer-events: none;
  z-index: 30;
  opacity: 0;
  transition: opacity 0.15s ease-in;
}

.game-power-label.visible {
  opacity: 1;
}
```

Replace the existing `pb-flash` animation with the enhanced slide-in version:

```css
.game-leaderboard-row.new-pb {
  animation: pb-slide-in 1.2s ease-out forwards;
}

@keyframes pb-slide-in {
  0%   { transform: translateX(16px); background-color: rgba(234, 179, 8, 0.45); }
  25%  { transform: translateX(0);    background-color: rgba(234, 179, 8, 0.45); }
  100% { transform: translateX(0);    background-color: transparent; }
}
```

- [ ] **Step 3: Register `aimZones` and `powerLabel` targets**

In `static targets`, add `"aimZones"` and `"powerLabel"`:

```javascript
static targets = [
  "setupSection", "playSection",
  "friendGrid", "startBtn",
  "playingAsLabel", "streakLabel", "pbLabel",
  "goalPost", "cursor", "ghostBall", "ballMark", "keeper", "resultOverlay", "resultText",
  "screenFlash", "netRipple", "aimZones", "powerLabel",
  "directionWrapper", "directionFill", "directionCursor",
  "powerWrapper", "powerFill", "powerCursor",
  "hintText", "ballBtn", "playAgainBtn", "leaderboard", "emptyLeaderboard"
]
```

Also add `aimZoneTimeout` to `connect()` initialisation:

```javascript
connect() {
  this.streak          = 0
  this.selectedFriend  = null
  this.dirPct          = 0
  this.dirDir          = 1
  this.pwrPct          = 0
  this.pwrDir          = 1
  this.dirLocked       = false
  this.shotFired       = false
  this.directionZone   = null
  this.actualDiveZone  = null
  this.raf             = null
  this.tapTimeout      = null
  this.aimZoneTimeout  = null
  ...
}
```

- [ ] **Step 4: Show aim zones in `_startDirectionBar()`, hide in `lockDirection()`**

In `_startDirectionBar()`, add near the end:

```javascript
// Show aim zone labels after 200ms so they don't flash on quick taps
clearTimeout(this.aimZoneTimeout)
this.aimZonesTarget.classList.remove("visible")
this.aimZoneTimeout = setTimeout(() => {
  this.aimZonesTarget.classList.add("visible")
}, 200)
```

In `lockDirection()`, hide immediately:

```javascript
lockDirection() {
  if (this.dirLocked) return
  this._clearTapTimeout()
  clearTimeout(this.aimZoneTimeout)
  this.aimZonesTarget.classList.remove("visible")
  cancelAnimationFrame(this.raf)
  this.dirLocked     = true
  this.directionZone = zone(this.dirPct)
  this.directionMiss = isMissDirection(this.dirPct)
  this.directionWrapperTarget.classList.add("locked-flash")
  setTimeout(() => this.directionWrapperTarget.classList.remove("locked-flash"), 250)
  this._startPowerBar()
}
```

Also clear in `switchPlayer()` and `_onTimeout()`:

```javascript
// In switchPlayer():
clearTimeout(this.aimZoneTimeout)
this.aimZonesTarget.classList.remove("visible")

// In _onTimeout():
clearTimeout(this.aimZoneTimeout)
this.aimZonesTarget.classList.remove("visible")
```

- [ ] **Step 5: Show power label in `_resolveShot()`, hide in `_showResult()`**

In `_resolveShot()`, after hiding cursor and ghost ball:

```javascript
// Show power level label briefly before result appears
const powerLabels = { low: "LOW", mid: "MID", high: "HIGH" }
this.powerLabelTarget.textContent = powerLabels[power]
this.powerLabelTarget.style.left  = `${this.dirPct}%`
this.powerLabelTarget.classList.add("visible")
```

In `_showResult()`, at the very start, hide the power label:

```javascript
_showResult(result) {
  this.powerLabelTarget.classList.remove("visible")
  this._flashScreen(result)
  ...
}
```

- [ ] **Step 6: Verify in browser**

1. Start a round — "LEFT / CENTRE / RIGHT" labels fade in on the goal after 200ms
2. Tap to lock aim — labels instantly disappear
3. Fire a shot — a small "LOW / MID / HIGH" label fades in near the ball mark, disappears when the result shows
4. Score a new PB — leaderboard row slides in from the right with a gold highlight

- [ ] **Step 7: Commit**

```bash
git add app/views/games/index.html.erb app/assets/tailwind/components/game.css app/javascript/controllers/penalty_game_controller.js
git commit -m "feat: aim zone labels, power level label, enhanced new-PB animation"
```
