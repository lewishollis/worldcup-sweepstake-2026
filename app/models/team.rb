class Team < ApplicationRecord
  # Main knockout bracket — appearing in any of these earns the +1 qualification bonus
  MAIN_KNOCKOUT_STAGES = ['Last 32', 'Last 16', 'Quarter-finals', 'Semi-finals', 'Final'].freeze
  # All knockout stages including the bronze final (used for progressed? check)
  KNOCKOUT_STAGES = (MAIN_KNOCKOUT_STAGES + ['3rd Place Final']).freeze

  has_many :home_matches, class_name: 'Match', foreign_key: 'home_team_id'
  has_many :away_matches, class_name: 'Match', foreign_key: 'away_team_id'
  has_and_belongs_to_many :groups
  has_one :friend
  has_many :friend_groups
  has_many :friends, through: :friend_groups

  def progression_score
    all_matches = home_matches.to_a + away_matches.to_a
    knockout_played = all_matches.select { |m| m.status == 'PostEvent' && KNOCKOUT_STAGES.include?(m.stage) }
    return 0.0 if knockout_played.none?

    # +1 for qualifying only if they appeared in the main bracket (not just the bronze final)
    score = knockout_played.any? { |m| MAIN_KNOCKOUT_STAGES.include?(m.stage) } ? 1.0 : 0.0

    knockout_played.each do |match|
      won = (match.home_team_id == id && match.winner == 'home') ||
            (match.away_team_id == id && match.winner == 'away')
      score += match.stage == '3rd Place Final' ? 0.5 : 1.0 if won
    end
    score
  end

  def progressed?
    all_matches = home_matches.to_a + away_matches.to_a
    all_matches.any? { |m| m.status == 'PostEvent' && KNOCKOUT_STAGES.include?(m.stage) }
  end

  def matches
    Match.where("home_team_id = :team_id OR away_team_id = :team_id", team_id: id)
  end
end
