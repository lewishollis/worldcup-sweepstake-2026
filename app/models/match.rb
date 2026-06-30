class Match < ApplicationRecord
  belongs_to :home_team, class_name: 'Team'
  belongs_to :away_team, class_name: 'Team'

  validates :match_id, uniqueness: true

  attr_accessor :home_friend_name, :away_friend_name
  # Transient live-match details (clock, goals, cards) — fetched per request,
  # never persisted.
  attr_accessor :live_clock, :home_events, :away_events
  attribute :home_friend_profile_picture_url, :string
  attribute :away_friend_profile_picture_url, :string
  attribute :match_status, :string
  def result_for(team)
    return 'TBC' unless status == 'PostEvent'

    if home_score == away_score
      # Knockout matches can't end in a draw — use the stored winner (set after AET/penalties)
      if winner == 'home'
        team == home_team ? 'Win (pens)' : 'Lost (pens)'
      elsif winner == 'away'
        team == away_team ? 'Win (pens)' : 'Lost (pens)'
      else
        'Draw'
      end
    elsif team == home_team
      home_score > away_score ? 'Win' : 'Lost'
    elsif team == away_team
      away_score > home_score ? 'Win' : 'Lost'
    else
      'TBC'
    end
  end
end
