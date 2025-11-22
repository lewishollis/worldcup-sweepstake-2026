class AddProfilePictureUrlsToMatches < ActiveRecord::Migration[7.0]
  def change
    add_column :matches, :home_friend_profile_picture_url, :string
    add_column :matches, :away_friend_profile_picture_url, :string
  end
end
