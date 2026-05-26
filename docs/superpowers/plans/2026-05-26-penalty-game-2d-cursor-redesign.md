# Penalty Game — 2D Crosshair Cursor Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the penalty game aim cursor move in 2D so players can see exactly where the ball will land — left/right during phase 1, up/down during phase 2 — with the cursor visibly escaping above the crossbar on an over-bar miss.

**Architecture:** Three files change. CSS removes the hard-coded `top: 50%` from `.game-cursor` and adds `overflow: visible` to the goal container so the cursor can escape upward. The Stimulus controller gains one new method (`_updateHeightUI`) and calls it each power animation frame. HTML updates two bar labels.

**Tech Stack:** Stimulus (Hotwire), Tailwind CSS, Rails ERB

---

### Task 1: CSS — free the cursor from its fixed vertical position

**Files:**
- Modify: `app/assets/tailwind/components/game.css`

- [ ] **Step 1: Remove `top: 50%` from `.game-cursor` and add `overflow: visible` to `.game-goal-post`**

Find `.game-cursor` (line ~48) and remove the `top: 50%;` line. Also find `.game-goal-post` and add `overflow: visible;`.

Before (`.game-cursor`):
```css
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
```

After (`.game-cursor`):
```css
.game-cursor {
  @apply absolute pointer-events-none;
  width: 16px;
  height: 16px;
  border-radius: 50%;
  background: rgba(255, 255, 0, 0.85);
  box-shadow: 0 0 8px 2px rgba(255, 255, 0, 0.5);
  transform: translate(-50%, -50%);
}
```

Find `.game-goal-post` and add `overflow: visible;` so the cursor can escape above the crossbar:
```css
.game-goal-post {
  @apply relative border-4 border-white mx-auto;
  width: 240px;
  height: 130px;
  border-bottom: none;
  overflow: visible;
  background: rgba(0, 0, 0, 0.35);
  background-image:
    repeating-linear-gradient(90deg, rgba(255,255,255,0.07) 0, rgba(255,255,255,0.07) 1px, transparent 1px, transparent 24px),
    repeating-linear-gradient(180deg, rgba(255,255,255,0.07) 0, rgba(255,255,255,0.07) 1px, transparent 1px, transparent 24px);
}
```

- [ ] **Step 2: Commit**

```bash
git add app/assets/tailwind/components/game.css
git commit -m "style: free game cursor from fixed top position, allow goal overflow"
```

---

### Task 2: JS — set cursor to ground level during Phase 1

**Files:**
- Modify: `app/javascript/controllers/penalty_game_controller.js`

The `_updateDirectionUI` method currently sets `cursorTarget.style.left` but never sets `top`. Now that CSS no longer anchors `top: 50%`, JS must set it explicitly during the aim phase. Ground level is `top: 85%` (cursor center, per `transform: translate(-50%, -50%)`).

- [ ] **Step 1: Update `_updateDirectionUI` to set `top: 85%`**

Find `_updateDirectionUI()` (around line 354) and add one line:

Before:
```javascript
_updateDirectionUI() {
  const pct     = this.dirPct
  const goalPct = 5 + (pct / 100) * 90   // clamp cursor 5–95% across goal width
  this.directionFillTarget.style.width  = `${pct}%`
  this.directionCursorTarget.style.left = `${pct}%`
  this.cursorTarget.style.left          = `${goalPct}%`
}
```

After:
```javascript
_updateDirectionUI() {
  const pct     = this.dirPct
  const goalPct = 5 + (pct / 100) * 90   // clamp cursor 5–95% across goal width
  this.directionFillTarget.style.width  = `${pct}%`
  this.directionCursorTarget.style.left = `${pct}%`
  this.cursorTarget.style.left          = `${goalPct}%`
  this.cursorTarget.style.top           = '85%'
}
```

- [ ] **Step 2: Verify in browser**

Start the dev server (`bin/dev` or `rails s`) and open the penalty game. Select a player and start. Confirm the yellow cursor sits near the bottom of the goal during the aim phase and sweeps left/right. It should not be at the vertical midpoint anymore.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/penalty_game_controller.js
git commit -m "feat: anchor aim cursor to ground level (top: 85%) during phase 1"
```

---

### Task 3: JS — add vertical cursor movement during Phase 2

**Files:**
- Modify: `app/javascript/controllers/penalty_game_controller.js`

Add a new `_updateHeightUI(pct)` method and call it from `_sweepPower`. The cursor rises as power increases, reaches the crossbar (`top: 0%`) at `pwrPct = 92` (the miss threshold), and continues to `top: -20%` at `pwrPct = 100` so the overshoot is clearly visible.

- [ ] **Step 1: Add `_updateHeightUI` method**

Add this method anywhere in the class (e.g. after `_sweepPower`):

```javascript
_updateHeightUI(pct) {
  let topPct
  if (pct <= 92) {
    topPct = 85 - (pct / 92) * 85          // 0 → 85%, 92 → 0%
  } else {
    topPct = -((pct - 92) / 8) * 20        // 92 → 0%, 100 → -20%
  }
  this.cursorTarget.style.top = `${topPct}%`
}
```

- [ ] **Step 2: Call `_updateHeightUI` from `_sweepPower`**

Find `_sweepPower` (around line 397) and add the call after updating the bar:

Before:
```javascript
_sweepPower(ts) {
  if (this.lastFrameTime !== null) {
    const delta = (ts - this.lastFrameTime) / 1000
    this.pwrPct += POWER_SPEED * delta * this.pwrDir
    if (this.pwrPct >= 100) { this.pwrPct = 100; this.pwrDir = -1 }
    if (this.pwrPct <= 0)   { this.pwrPct = 0;   this.pwrDir =  1 }
    this.powerFillTarget.style.width  = `${this.pwrPct}%`
    this.powerCursorTarget.style.left = `${this.pwrPct}%`
  }
  this.lastFrameTime = ts
  this.raf = requestAnimationFrame((ts) => this._sweepPower(ts))
}
```

After:
```javascript
_sweepPower(ts) {
  if (this.lastFrameTime !== null) {
    const delta = (ts - this.lastFrameTime) / 1000
    this.pwrPct += POWER_SPEED * delta * this.pwrDir
    if (this.pwrPct >= 100) { this.pwrPct = 100; this.pwrDir = -1 }
    if (this.pwrPct <= 0)   { this.pwrPct = 0;   this.pwrDir =  1 }
    this.powerFillTarget.style.width  = `${this.pwrPct}%`
    this.powerCursorTarget.style.left = `${this.pwrPct}%`
    this._updateHeightUI(this.pwrPct)
  }
  this.lastFrameTime = ts
  this.raf = requestAnimationFrame((ts) => this._sweepPower(ts))
}
```

- [ ] **Step 3: Verify in browser**

Open the penalty game. After tapping to lock aim, watch the cursor during the power phase. Confirm:
1. Cursor rises from near the ground toward the crossbar
2. At the moment before the bar hits the red zone (~92%), the cursor is near the top of the goal
3. If you wait and let the bar hit max, the cursor visibly exits above the crossbar

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/penalty_game_controller.js
git commit -m "feat: add vertical cursor movement in phase 2, escapes goal above 92% power"
```

---

### Task 4: Update labels and hint text

**Files:**
- Modify: `app/views/games/index.html.erb`
- Modify: `app/javascript/controllers/penalty_game_controller.js`

- [ ] **Step 1: Update bar labels in the HTML template**

In `app/views/games/index.html.erb`, find the two `.game-bar-label` divs and update them:

Find (direction bar label, around line 62):
```erb
<div class="game-bar-label">DIRECTION ← →</div>
```
Replace with:
```erb
<div class="game-bar-label">AIM ←→</div>
```

Find (power bar label, around line 74):
```erb
<div class="game-bar-label">POWER ↑</div>
```
Replace with:
```erb
<div class="game-bar-label">POWER ↕</div>
```

- [ ] **Step 2: Update power phase hint text in the JS controller**

In `app/javascript/controllers/penalty_game_controller.js`, find `_startPowerBar` (around line 387):

Before:
```javascript
this.hintTextTarget.textContent = "Tap the ball to shoot!"
```

After:
```javascript
this.hintTextTarget.textContent = "Tap to shoot — stop it before it flies over the bar!"
```

- [ ] **Step 3: Verify in browser**

Confirm the direction bar now reads "AIM ←→", the power bar reads "POWER ↕", and the hint text updates correctly after the first tap.

- [ ] **Step 4: Commit**

```bash
git add app/views/games/index.html.erb app/javascript/controllers/penalty_game_controller.js
git commit -m "feat: update bar labels to AIM and POWER, improve shoot hint text"
```

---

### Task 5: Update how-to-play modal copy

**Files:**
- Modify: `app/javascript/controllers/penalty_game_controller.js`

- [ ] **Step 1: Update the steps array in `_showHowToPlayModal`**

Find the `steps` array in `_showHowToPlayModal` (around line 247):

Before:
```javascript
const steps = [
  { title: "Aim",              desc: "Tap the ball to lock the direction bar" },
  { title: "Shoot",            desc: "Tap again to lock your power" },
  { title: "Score streaks 🔥", desc: "Avoid the red zones — that's a miss" },
]
```

After:
```javascript
const steps = [
  { title: "Aim",              desc: "Tap to aim — stop the crosshair left, centre, or right." },
  { title: "Shoot",            desc: "Tap to shoot — stop it before it flies over the bar." },
  { title: "Score streaks 🔥", desc: "Avoid the red zones — that's a miss" },
]
```

- [ ] **Step 2: Verify in browser**

Hard-refresh the page (clear session storage so the how-to-play modal appears: open DevTools → Application → Session Storage → clear `penalty_game_friend`). Confirm the modal shows the new step descriptions.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/penalty_game_controller.js
git commit -m "feat: update how-to-play modal copy to match 2D cursor mechanic"
```

---

### Task 6: Full end-to-end verification

**Files:** none — verification only

- [ ] **Step 1: Test a normal goal**

Play a round. Lock aim in the center (green zone), lock power in the mid range (cursor mid-height in goal). Confirm "GOAL ⚽" appears and the ball mark lands roughly where the cursor was.

- [ ] **Step 2: Test a wide miss**

Lock aim in the red zone (far left or far right). Confirm the cursor is near the post, shot is wide, "MISSED ↗" appears.

- [ ] **Step 3: Test an over-the-bar miss**

Let the power bar run into the red zone on the right. Confirm:
1. The cursor visibly exits above the crossbar
2. "MISSED ↗" (or the existing over-bar result text) appears
3. The ball mark appears above the goal frame

- [ ] **Step 4: Test play-again flow**

After any miss, click "Play Again". Confirm the cursor returns to the ground level (bottom of goal) at the start of the new aim phase — not floating at a mid or high position.

- [ ] **Step 5: Test on mobile viewport**

Resize to a mobile width (375px) or use DevTools device emulation. Confirm the cursor remains visible and the escape-above-crossbar effect still works at small sizes.
