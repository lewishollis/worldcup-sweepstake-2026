Rails.application.routes.draw do
  # Define routes for MatchesController
  resources :matches, only: [:index, :show]

  # Define routes for LeaderboardController
  resources :leaderboard, only: [:index, :show] do
    patch :update_team_progress, on: :member
  end

  # Set root route
  root 'matches#index'
end
