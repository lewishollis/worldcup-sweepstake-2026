class Group < ApplicationRecord
  has_and_belongs_to_many :teams
  belongs_to :friend, optional: true

  def calculate_score
    self.score = total_points
    save(validate: false)
  end

  def total_points
    teams.sum { |team| team.points + (team.progressed? ? 1 : 0) } * multiplier
  end
end
