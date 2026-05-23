class CreateNewsItems < ActiveRecord::Migration[7.1]
  def change
    create_table :news_items do |t|
      t.string :title
      t.text :summary
      t.string :guid
      t.datetime :published_at

      t.timestamps
    end
    add_index :news_items, :guid, unique: true
  end
end
