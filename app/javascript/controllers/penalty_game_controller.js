// app/javascript/controllers/penalty_game_controller.js
import { Controller } from "@hotwired/stimulus"

const SPEED_LEVELS = [
  { upTo: 3,        dir: 70,  pwr: 60  },
  { upTo: 6,        dir: 110, pwr: 100 },
  { upTo: 10,       dir: 160, pwr: 145 },
  { upTo: Infinity, dir: 210, pwr: 190 },
]

function speedForStreak(streak) {
  return SPEED_LEVELS.find(s => streak < s.upTo)
}

const DIRECTION_MISS_EDGE = 8    // 0–8% or 92–100% = too wide (miss)
const POWER_MISS_EDGE     = 92   // 92–100% = over the bar (miss)
const KEEPER_ZONES        = ["left", "center", "right"]

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

function powerLevel(pct) {
  if (pct < 33) return "low"
  if (pct < 67) return "mid"
  return "high"
}

function saveChance(power) {
  if (power === "low")  return 1.0  // comfortable catch
  if (power === "mid")  return 0.8  // keeper strains
  return 0.45                       // hard to hold
}

function isMissDirection(pct) {
  return pct < DIRECTION_MISS_EDGE || pct > (100 - DIRECTION_MISS_EDGE)
}

function isMissPower(pct) {
  return pct > POWER_MISS_EDGE
}

function timeAgo(isoString) {
  if (!isoString) return ""
  const diff = Math.floor((Date.now() - new Date(isoString)) / 1000)
  if (diff < 60)    return `${diff}s ago`
  if (diff < 3600)  return `${Math.floor(diff / 60)}m ago`
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`
  return `${Math.floor(diff / 86400)}d ago`
}

// Minimal element builder — reduces modal-building boilerplate
function el(tag, cssText = "", text = "") {
  const node = document.createElement(tag)
  if (cssText) node.style.cssText = cssText
  if (text)    node.textContent   = text
  return node
}

export default class extends Controller {
  static targets = [
    "setupSection", "playSection",
    "friendGrid", "startBtn",
    "playingAsLabel", "streakLabel", "pbLabel",
    "goalPost", "cursor", "ghostBall", "ballMark", "keeper", "resultOverlay", "resultText",
    "directionWrapper", "directionFill", "directionCursor",
    "powerWrapper", "powerFill", "powerCursor",
    "hintText", "ballBtn", "playAgainBtn", "leaderboard", "emptyLeaderboard"
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
    this.shotFired       = false
    this.directionZone   = null
    this.actualDiveZone  = null
    this.raf             = null
    this.tapTimeout      = null

    this._renderFriendGrid()
    this._renderLeaderboard(this.leaderboardValue)
    this._showHowToPlayModal()

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
    this.cursorTarget.classList.add("hidden")
    this.streak = 0
    this._updateStreakLabel()
    this.resultOverlayTarget.classList.remove("hidden")
    this.playAgainBtnTarget.classList.remove("hidden")
    const text = this.resultTextTarget
    text.textContent = "TIMED OUT ⌛"
    text.className   = "game-result-text missed"
  }

  // ── Friend picker ────────────────────────────────────────

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
    this._showPlayerConfirmPopup(friend)
  }

  _showPlayerConfirmPopup(friend) {
    const existing = document.getElementById("player-confirm-popup")
    if (existing) existing.remove()

    const overlay = el("div", "position:fixed;inset:0;display:flex;align-items:center;justify-content:center;z-index:9999;background:rgba(0,0,0,0.55);backdrop-filter:blur(2px)")
    overlay.id    = "player-confirm-popup"
    const card    = el("div", "background:#1a1a2e;border:2px solid #4a9d6f;border-radius:16px;padding:28px 32px;text-align:center;max-width:280px;width:90%;box-shadow:0 8px 40px rgba(0,0,0,0.6)")
    const emoji   = el("div", "font-size:2.5rem;margin-bottom:8px", "⚽")
    const nameEl  = el("div", "color:#fff;font-size:1.15rem;font-weight:700;margin-bottom:4px", friend.name)
    const sub     = el("div", "color:#a0a0c0;font-size:0.85rem;margin-bottom:20px", "Ready to take penalties?")
    const playBtn = el("button", "background:#4a9d6f;color:#fff;border:none;border-radius:10px;padding:12px 32px;font-size:1rem;font-weight:700;cursor:pointer;width:100%", "Play ⚽")

    playBtn.addEventListener("click", () => { overlay.remove(); this.startGame() })
    overlay.addEventListener("click", (e) => { if (e.target === overlay) overlay.remove() })

    card.append(emoji, nameEl, sub, playBtn)
    overlay.appendChild(card)
    document.body.appendChild(overlay)
    playBtn.focus()
  }

  _showHowToPlayModal() {
    const overlay   = el("div", "position:fixed;inset:0;display:flex;align-items:center;justify-content:center;z-index:9999;background:rgba(0,0,0,0.65);backdrop-filter:blur(3px)")
    const card      = el("div", "background:#1a1a2e;border:2px solid #4a9d6f;border-radius:16px;padding:28px 24px;width:88%;max-width:300px;text-align:center;box-shadow:0 8px 40px rgba(0,0,0,0.7)")
    const icon      = el("div", "font-size:2rem;margin-bottom:4px", "⚽")
    const heading   = el("div", "color:#fff;font-size:1.1rem;font-weight:800;margin-bottom:2px", "How to Play")
    const sub       = el("div", "color:#7a7a9a;font-size:0.78rem;margin-bottom:20px", "Penalty Shootout")
    const stepsList = el("div", "display:flex;flex-direction:column;gap:10px;margin-bottom:22px;text-align:left")

    const steps = [
      { title: "Aim",              desc: "Tap the ball to aim — stop the cursor left, centre, or right." },
      { title: "Shoot",            desc: "Tap to shoot — stop it before it flies over the bar." },
      { title: "Score streaks 🔥", desc: "Avoid the red zones — that's a miss." },
      { title: "Get harder ⏩",    desc: "The longer your streak, the faster the bars move." },
    ]

    steps.forEach((s, i) => {
      const row   = el("div", "display:flex;align-items:center;gap:12px;background:#0f0f1a;border-radius:10px;padding:10px 12px")
      const num   = el("div", "background:#4a9d6f;color:#fff;font-weight:800;font-size:0.8rem;width:24px;height:24px;border-radius:50%;display:flex;align-items:center;justify-content:center;flex-shrink:0", String(i + 1))
      const wrap  = el("div")
      const title = el("div", "color:#fff;font-size:0.82rem;font-weight:600", s.title)
      const desc  = el("div", "color:#7a7a9a;font-size:0.74rem", s.desc)
      wrap.append(title, desc)
      row.append(num, wrap)
      stepsList.appendChild(row)
    })

    const btn = el("button", "background:#4a9d6f;color:#fff;border:none;border-radius:10px;padding:12px 0;font-size:0.95rem;font-weight:700;cursor:pointer;width:100%", "Got it, let's play!")
    btn.addEventListener("click", () => overlay.remove())

    card.append(icon, heading, sub, stepsList, btn)
    overlay.appendChild(card)
    document.body.appendChild(overlay)
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
    this._clearTapTimeout()
    sessionStorage.removeItem("penalty_game_friend")
    this.selectedFriend = null
    this.streak         = 0
    this.playSectionTarget.classList.add("hidden")
    this.setupSectionTarget.classList.remove("hidden")
    this.startBtnTarget.disabled = true
    this.friendGridTarget.querySelectorAll(".game-friend-btn").forEach(b => b.classList.remove("selected"))
    this._resetBars()
  }

  // ── Direction bar ────────────────────────────────────────

  _startDirectionBar() {
    this.dirLocked = false
    this.shotFired = false
    this.dirPct    = 0
    this.dirDir    = 1
    this.cursorTarget.style.top = "85%"
    this.ghostBallTarget.style.opacity  = "1"
    this.ghostBallTarget.style.left     = "50%"
    this.ghostBallTarget.style.top      = "85%"
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

  _sweepDirection(ts) {
    if (this.dirLocked) return
    if (this.lastFrameTime !== null) {
      const delta = (ts - this.lastFrameTime) / 1000
      this.dirPct += speedForStreak(this.streak).dir * delta * this.dirDir
      if (this.dirPct >= 100) { this.dirPct = 100; this.dirDir = -1 }
      if (this.dirPct <= 0)   { this.dirPct = 0;   this.dirDir =  1 }
      this._updateDirectionUI()
    }
    this.lastFrameTime = ts
    this.raf = requestAnimationFrame((ts) => this._sweepDirection(ts))
  }

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

  tapBall() {
    if (!this.dirLocked) {
      this.lockDirection()
    } else {
      this.lockPower()
    }
  }

  lockDirection() {
    if (this.dirLocked) return
    this._clearTapTimeout()
    cancelAnimationFrame(this.raf)
    this.dirLocked     = true
    this.directionZone = zone(this.dirPct)
    this.directionMiss = isMissDirection(this.dirPct)
    this._startPowerBar()
  }

  _pickKeeperDiveZone() {
    this.actualDiveZone = KEEPER_ZONES[Math.floor(Math.random() * KEEPER_ZONES.length)]
  }

  // ── Power bar ────────────────────────────────────────────

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

  _sweepPower(ts) {
    if (this.lastFrameTime !== null) {
      const delta = (ts - this.lastFrameTime) / 1000
      this.pwrPct += speedForStreak(this.streak).pwr * delta * this.pwrDir
      if (this.pwrPct >= 100) { this.pwrPct = 100; this.pwrDir = -1 }
      if (this.pwrPct <= 0)   { this.pwrPct = 0;   this.pwrDir =  1 }
      this.powerFillTarget.style.width  = `${this.pwrPct}%`
      this.powerCursorTarget.style.left = `${this.pwrPct}%`
      this._updateHeightUI(this.pwrPct)
    }
    this.lastFrameTime = ts
    this.raf = requestAnimationFrame((ts) => this._sweepPower(ts))
  }

  _updateHeightUI(pct) {
    // 0 → 85% (ground), POWER_MISS_EDGE → 0% (crossbar), 100 → -20% (above bar)
    const topPct = pct <= POWER_MISS_EDGE
      ? 85 - (pct / POWER_MISS_EDGE) * 85
      : -((pct - POWER_MISS_EDGE) / (100 - POWER_MISS_EDGE)) * 20
    this.cursorTarget.style.top    = `${topPct}%`
    this.ghostBallTarget.style.top = `${topPct}%`
  }

  lockPower() {
    if (this.shotFired) return
    this.shotFired = true
    this._clearTapTimeout()
    cancelAnimationFrame(this.raf)
    this._resolveShot(powerLevel(this.pwrPct), isMissPower(this.pwrPct))
  }

  // ── Shot resolution ──────────────────────────────────────

  _placeBallMark() {
    const mark = this.ballMarkTarget

    let finalLeft, finalTop
    if (this.directionMiss) {
      // Wide shot — outside the posts, scaled by power
      const wideLeft = this.dirPct < DIRECTION_MISS_EDGE
      const offset   = 5 + this.pwrPct * 0.25  // 5% (low power) → 30% (high power) outside post
      finalLeft = wideLeft ? `-${offset}%` : `${100 + offset}%`
      finalTop  = `${Math.round(82 - this.pwrPct * 0.77)}%`
      mark.classList.add("miss")
    } else if (isMissPower(this.pwrPct)) {
      // Over the bar — above the crossbar
      finalLeft = `${this.dirPct}%`
      finalTop  = "-25%"
      mark.classList.add("miss")
    } else {
      // Normal shot — y: low power = near ground, high power = near crossbar
      finalLeft = `${this.dirPct}%`
      finalTop  = `${Math.round(82 - this.pwrPct * 0.77)}%`
      mark.classList.remove("miss")
    }

    mark.style.left = "50%"
    mark.style.top  = "90%"
    mark.classList.remove("hidden")
    void mark.offsetWidth  // force reflow so CSS transition fires from origin
    mark.style.left = finalLeft
    mark.style.top  = finalTop
  }

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

  _showResult(result) {
    this.resultOverlayTarget.classList.remove("hidden")
    const text = this.resultTextTarget

    if (result === "goal") {
      this.streak++
      this._updateStreakLabel()
      text.textContent = "GOAL ⚽"
      text.className   = "game-result-text goal"
      this.playAgainBtnTarget.classList.add("hidden")
      this.hintTextTarget.textContent = this.streak >= 3 ? `${this.streak} in a row! 🔥` : "Next up…"
      setTimeout(() => this._startDirectionBar(), 1200)
      return
    }

    text.textContent = result === "missed" ? "MISSED ↗" : "SAVED 🧤"
    text.className   = `game-result-text ${result}`
    this.playAgainBtnTarget.classList.remove("hidden")
    this._saveScore()
  }

  playAgain() {
    this.streak = 0
    this._updateStreakLabel()
    this._startDirectionBar()
  }

  // ── Score persistence ────────────────────────────────────

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

  // ── Leaderboard rendering ────────────────────────────────

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

      const rank = document.createElement("span")
      rank.className = `game-leaderboard-rank ${rankClasses[i] || ""}`
      rank.textContent = i + 1
      row.appendChild(rank)

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

      const name = document.createElement("span")
      name.className = "game-leaderboard-name"
      name.textContent = entry.friend_name
      row.appendChild(name)

      const streak = document.createElement("span")
      streak.className = "game-leaderboard-streak"
      streak.textContent = `${entry.best_streak} 🔥`
      row.appendChild(streak)

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
    this.cursorTarget.style.top           = "85%"
  }
}
