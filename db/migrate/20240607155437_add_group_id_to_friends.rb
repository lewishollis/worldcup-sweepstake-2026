class AddGroupIdToFriends < ActiveRecord::Migration[7.0]
  def change
    add_reference :friends, :group, foreign_key: true
  end
end
