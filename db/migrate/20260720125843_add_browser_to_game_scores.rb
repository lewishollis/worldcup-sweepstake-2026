class AddBrowserToGameScores < ActiveRecord::Migration[7.1]
  def change
    add_column :game_scores, :browser, :string
  end
end
