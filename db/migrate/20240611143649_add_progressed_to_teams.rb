class AddProgressedToTeams < ActiveRecord::Migration[7.0]
  def change
    add_column :teams, :progressed, :boolean
  end
end
