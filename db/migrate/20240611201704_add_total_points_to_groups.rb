class AddTotalPointsToGroups < ActiveRecord::Migration[7.0]
  def change
    add_column :groups, :total_points, :integer
  end
end
