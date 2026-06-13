class AddFifaRankToTeams < ActiveRecord::Migration[7.1]
  def up
    add_column :teams, :fifa_rank, :integer

    # Backfill the snapshot onto existing rows (runs on deploy via db:prepare),
    # so production teams get their ranking without a re-seed. Match by name.
    Team.reset_column_information
    Team::FIFA_RANKS.each do |name, rank|
      Team.where(name: name).update_all(fifa_rank: rank)
    end
  end

  def down
    remove_column :teams, :fifa_rank
  end
end
