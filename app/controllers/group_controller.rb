class GroupController < ApplicationRecord
  has_and_belongs_to_many :teams

  def calculate_score
    total_team_points = teams.sum(:points)
    self.score = total_team_points * multiplier
  end
end
