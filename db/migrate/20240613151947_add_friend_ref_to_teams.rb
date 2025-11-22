class AddFriendRefToTeams < ActiveRecord::Migration[7.0]
  def change
    add_reference :teams, :friends, foreign_key: true
  end
end
