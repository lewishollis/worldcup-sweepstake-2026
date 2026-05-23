class AddScenarioInsightToMatches < ActiveRecord::Migration[7.1]
  def change
    add_column :matches, :scenario_insight, :text
    add_column :matches, :scenario_insight_cache_key, :string
  end
end
