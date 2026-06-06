class RemoveDeadScoringColumns < ActiveRecord::Migration[7.1]
  def change
    remove_column :teams, :points, :integer
    remove_column :teams, :progressed, :boolean

    remove_column :matches, :home_points, :integer
    remove_column :matches, :away_points, :integer
    remove_column :matches, :result, :string

    remove_column :groups, :multiplier, :float
    remove_column :groups, :score, :float
    remove_column :groups, :total_points, :integer
  end
end
