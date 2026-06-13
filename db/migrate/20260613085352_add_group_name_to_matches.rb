class AddGroupNameToMatches < ActiveRecord::Migration[7.1]
  def change
    add_column :matches, :group_name, :string
  end
end
