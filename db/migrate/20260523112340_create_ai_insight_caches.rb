class CreateAiInsightCaches < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_insight_caches do |t|
      t.string :key
      t.text :content
      t.string :version
      t.datetime :generated_at

      t.timestamps
    end
    add_index :ai_insight_caches, :key, unique: true
  end
end
