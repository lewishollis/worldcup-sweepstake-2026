class AddTeamReferencesToMatches < ActiveRecord::Migration[7.0]
  def change
    add_reference :matches, :team, foreign_key: true
  end
end
