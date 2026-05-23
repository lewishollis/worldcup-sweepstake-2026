class AiInsightCache < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :content, presence: true

  def self.fetch(key:, version:)
    record = find_by(key: key)
    return record.content if record&.version == version
    nil
  end

  def self.store(key:, version:, content:)
    find_or_initialize_by(key: key).tap do |r|
      r.update!(content: content, version: version, generated_at: Time.current)
    end
  end
end
