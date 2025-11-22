class CreateMatches < ActiveRecord::Migration[6.0]
  def change
    create_table :matches do |t|
      t.references :home_team, null: false, foreign_key: { to_table: :teams }
      t.references :away_team, null: false, foreign_key: { to_table: :teams }
      t.integer :home_score
      t.integer :away_score
      t.datetime :start_time
      t.string :status
      t.string :winner
      t.string :accessible_event_summary
      t.integer :home_points, default: 0
      t.integer :away_points, default: 0

      t.timestamps
    end
  end
end
