# app/models/game_score.rb
class GameScore < ApplicationRecord
  belongs_to :friend

  validates :streak, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1000 }

  # Deadline after which the penalty game freezes and no new scores are written.
  # Tuesday 21 July 2026, 11:00 UK (BST) == 10:00 UTC == 17:00 (5pm) Vietnam time (ICT).
  # Override in any environment with the GAME_DEADLINE env var (ISO 8601, e.g. "2026-07-21T10:00:00Z").
  DEADLINE = Time.iso8601(ENV.fetch("GAME_DEADLINE", "2026-07-21T10:00:00Z"))

  # True once the deadline has passed — the game is locked and rejects new scores.
  # Read-only paths (leaderboard, best_per_friend) are unaffected, so existing scores stay intact.
  def self.locked?(now = Time.current)
    now >= DEADLINE
  end

  # Audit trail: devices (browsers) that have submitted scores for more than one friend.
  # Returns a hash of device_id => array of distinct friend names, sorted by most friends first.
  # A device scoring for several friends is the tell-tale sign of one phone playing on others' behalf.
  def self.suspicious_devices
    where.not(device_id: nil)
      .includes(:friend)
      .group_by(&:device_id)
      .transform_values { |scores| scores.map { |s| s.friend.name }.uniq.sort }
      .select { |_device, names| names.size > 1 }
      .sort_by { |_device, names| -names.size }
      .to_h
  end

  # Returns best streak per friend, ordered descending, tie-broken by earliest achieved.
  # Each element is a hash with: friend_id, best_streak, first_achieved, friend
  def self.best_per_friend
    # Step 1: find best streak per friend
    best = includes(:friend)
      .select("friend_id, MAX(streak) AS best_streak")
      .group(:friend_id)

    # Step 2: resolve first_achieved (when best streak was first reached) and sort
    results = best.map do |row|
      first_achieved = where(friend_id: row.friend_id, streak: row.best_streak)
                         .minimum(:created_at)
      {
        friend_id: row.friend_id,
        best_streak: row.best_streak,
        first_achieved: first_achieved,
        friend: row.friend
      }
    end

    results.sort_by { |e| [-e[:best_streak], e[:first_achieved]] }
  end
end
