# db/migrate/20240605202423_create_teams.rb
class CreateTeams < ActiveRecord::Migration[7.0]
  def change
    create_table :teams do |t|
      t.string :name
      t.integer :points, default: 0

      t.timestamps
    end
  end
end
