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

function powerLevel(pct) {
  if (pct < 33) return "low"
  if (pct < 67) return "mid"
  return "high"
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
    const powerZone = powerLevel(this.pwrPct)
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
