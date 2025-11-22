class AddResultToMatches < ActiveRecord::Migration[7.0]
  def change
    add_column :matches, :result, :string
  end
end
