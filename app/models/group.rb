class Group < ApplicationRecord
  has_and_belongs_to_many :teams
  belongs_to :friend, optional: true

  def total_points
    teams.sum(&:progression_score)
  end
end
