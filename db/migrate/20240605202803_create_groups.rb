class CreateGroups < ActiveRecord::Migration[7.0]
  def change
    create_table :groups do |t|
      t.references :friend, foreign_key: true
      t.string :name
      t.float :multiplier, default: 1.0
      t.float :score, default: 0.0

      t.timestamps
    end

    create_table :groups_teams do |t|
      t.belongs_to :group
      t.belongs_to :team
    end
  end
end
