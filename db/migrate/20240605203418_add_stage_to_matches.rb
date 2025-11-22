class AddStageToMatches < ActiveRecord::Migration[7.0]
  def change
    add_column :matches, :stage, :string
  end
end
