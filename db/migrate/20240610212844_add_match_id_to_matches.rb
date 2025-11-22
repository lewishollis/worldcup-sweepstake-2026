class AddMatchIdToMatches < ActiveRecord::Migration[7.0]
  def change
    add_column :matches, :match_id, :string
    add_index :matches, :match_id
  end
end
