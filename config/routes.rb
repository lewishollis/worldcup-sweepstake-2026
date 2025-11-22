Rails.application.routes.draw do
  get 'faqs/index'

  # Define routes for MatchesController
  resources :matches, only: [:index, :show]  # Assuming you only need the index action for now

  # Define routes for LeaderboardController
  resources :leaderboard, only: [:index, :show]  do
    patch :update_team_progress, on: :member
  end  # Assuming you have an index action in LeaderboardController

  resources :friends, only: [:index, :show]
  resources :groups, only: [:index]
  # Add more routes for other controllers as needed
  resources :teams, only: [:index]
  # Set root route
  root 'matches#index'  # Assuming you want the matches index as the root route
    get 'faqs', to: 'faqs#index'
end
