# app/models/game_score.rb
class GameScore < ApplicationRecord
  belongs_to :friend

  validates :streak, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Returns best streak per friend, ordered descending, tie-broken by earliest achieved.
  # Each element is a hash with: friend_id, best_streak, first_achieved, friend
  def self.best_per_friend
    joins(:friend)
      .select("friend_id, MAX(streak) AS best_streak, MIN(game_scores.created_at) AS first_achieved")
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
