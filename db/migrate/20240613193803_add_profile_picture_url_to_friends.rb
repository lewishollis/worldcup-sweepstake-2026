class AddProfilePictureUrlToFriends < ActiveRecord::Migration[7.0]
  def change
    add_column :friends, :profile_picture_url, :string
  end
end
