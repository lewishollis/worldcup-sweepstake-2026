class CreateGameScores < ActiveRecord::Migration[7.1]
  def change
    create_table :game_scores do |t|
      t.references :friend, null: false, foreign_key: true
      t.integer :streak, null: false

      t.timestamps
    end
  end
end
