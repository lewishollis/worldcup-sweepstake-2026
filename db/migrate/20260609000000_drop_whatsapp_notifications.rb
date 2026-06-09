class DropWhatsappNotifications < ActiveRecord::Migration[7.1]
  def up
    drop_table :whatsapp_notifications
  end

  def down
    create_table :whatsapp_notifications do |t|
      t.string :notification_type, null: false
      t.string :dedupe_key, null: false
      t.datetime :sent_at
      t.references :match, foreign_key: true
      t.timestamps
    end
    add_index :whatsapp_notifications, :dedupe_key, unique: true
  end
end
