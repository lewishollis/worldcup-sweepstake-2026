class AddDeviceIdToGameScores < ActiveRecord::Migration[7.1]
  def change
    add_column :game_scores, :device_id, :string
  end
end
