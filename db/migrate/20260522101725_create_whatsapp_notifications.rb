class CreateWhatsappNotifications < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_notifications do |t|
      t.integer  :match_id
      t.string   :notification_type, null: false
      t.string   :dedupe_key, null: false
      t.datetime :sent_at, null: false
      t.timestamps
    end

    add_index :whatsapp_notifications, :dedupe_key, unique: true
    add_index :whatsapp_notifications, :match_id
  end
end
