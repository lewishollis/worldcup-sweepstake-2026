class TeamsController < ApplicationController
  def index
    @teams = Team.order(points: :desc)
  end
end
