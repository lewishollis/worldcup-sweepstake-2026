class CreateFriendGroupTeams < ActiveRecord::Migration[7.0]
  def change
    create_table :friend_group_teams do |t|
      t.references :friends_group,  foreign_key: true
      t.references :team, foreign_key: true

      t.timestamps
    end
  end
end
