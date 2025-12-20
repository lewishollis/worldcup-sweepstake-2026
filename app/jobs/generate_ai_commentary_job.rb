class GenerateAiCommentaryJob < ApplicationJob
  queue_as :default

  def perform
    # Find matches that need commentary (live or recently finished)
    matches = Match.where(status: ['MidEvent', 'PostEvent'])
                   .where('updated_at > ?', 2.hours.ago)

    matches.find_each do |match|
      # Skip if commentary was generated less than 5 minutes ago
      next if match.ai_commentary_generated_at.present? &&
              match.ai_commentary_generated_at > 5.minutes.ago

      AiCommentaryService.new(match).generate_commentary

      # Add small delay to avoid rate limiting
      sleep 1
    end
  end
end
