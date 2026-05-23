class NewsItem < ApplicationRecord
  validates :guid, presence: true, uniqueness: true
  validates :title, presence: true

  scope :recent, -> { order(published_at: :desc) }
end
