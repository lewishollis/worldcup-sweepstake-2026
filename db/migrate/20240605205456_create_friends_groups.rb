class CreateFriendsGroups < ActiveRecord::Migration[7.0]
  def change
    create_table :friends_groups do |t|
      t.string :name
      t.references :friend, foreign_key: true

      t.timestamps
    end
  end
end
