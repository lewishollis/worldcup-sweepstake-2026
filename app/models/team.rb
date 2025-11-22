class Team < ApplicationRecord
  has_many :home_matches, class_name: 'Match', foreign_key: 'home_team_id'
  has_many :away_matches, class_name: 'Match', foreign_key: 'away_team_id'
  has_and_belongs_to_many :groups
  has_one :friend
  has_many :friend_groups
  has_many :friends, through: :friend_groups
  attribute :points, :integer, default: 0
  before_save :update_group_scores, if: :will_save_change_to_points?

  def progressed?
    progressed
  end

  def matches
    Match.where("home_team_id = :team_id OR away_team_id = :team_id", team_id: id)
  end

  private

  def update_team_points(team, points)
    puts "Updating team points: Team: #{team.name}, Current Points: #{team.points}, Points to Add: #{points}"
    team.points = (team.points || 0) + points
    team.save!
    puts "New team points: Team: #{team.name}, Updated Points: #{team.points}"
  end


  def update_group_scores
    groups.each do |group|
      group.calculate_score
    end
  end
end
