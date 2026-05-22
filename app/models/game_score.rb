# app/models/game_score.rb
class GameScore < ApplicationRecord
  belongs_to :friend

  validates :streak, presence: true, numericality: { greater_than_or_equal_to: 0 }

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
