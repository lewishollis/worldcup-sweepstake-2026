class AddFlagUrlToTeams < ActiveRecord::Migration[7.0]
  def change
    add_column :teams, :flag_url, :string
  end
end
