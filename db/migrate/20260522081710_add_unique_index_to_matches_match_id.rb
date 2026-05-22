class AddUniqueIndexToMatchesMatchId < ActiveRecord::Migration[7.1]
  def change
    remove_index :matches, :match_id, if_exists: true
    add_index :matches, :match_id, unique: true
  end
end
