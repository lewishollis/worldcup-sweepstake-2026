class LeaderboardController < ApplicationController
  def index
    @groups = Group.includes(:teams, :friend).all.sort_by { |group| -group_total_points(group) }
  end

  def show
    @leaderboard = Group.includes(:friend).sort_by { |group| -group.total_points }
  end



  def update_team_progress
    team = Team.find(params[:id])
    team.update(progressed: !team.progressed?)
    redirect_to leaderboard_index_path
  end

  private

  def group_total_points(group)
    group.teams.sum(&:points).to_i
  end
end
