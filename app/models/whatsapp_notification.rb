class WhatsappNotification < ApplicationRecord
  validates :notification_type, presence: true
  validates :dedupe_key, presence: true, uniqueness: true
  validates :sent_at, presence: true
end
