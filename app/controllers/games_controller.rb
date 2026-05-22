class GamesController < ApplicationController
  def index
    @friends = Friend.all.order(:name)
    @leaderboard = leaderboard_data
  end

  def create
    friend = Friend.find_by(id: score_params[:friend_id])

    if friend.nil?
      render json: { error: "Friend not found" }, status: :unprocessable_entity
      return
    end

    score = GameScore.new(friend: friend, streak: score_params[:streak])

    if score.save
      render json: leaderboard_data
    else
      render json: { errors: score.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def scores
    render json: leaderboard_data
  end

  private

  def score_params
    params.permit(:friend_id, :streak)
  end

  def leaderboard_data
    GameScore.best_per_friend.map do |entry|
      {
        friend_id: entry[:friend_id],
        friend_name: entry[:friend].name,
        friend_picture_url: entry[:friend].profile_picture_url,
        best_streak: entry[:best_streak],
        first_achieved: entry[:first_achieved]
      }
    end
  end
end
