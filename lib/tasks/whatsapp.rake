namespace :whatsapp do
  desc "Send morning fixture digest if matches exist today and not already sent"
  task morning_digest: :environment do
    dedupe_key = "morning_digest:#{Time.current.to_date}"

    if WhatsappNotification.exists?(dedupe_key: dedupe_key)
      Rails.logger.info("[whatsapp:morning_digest] Already sent today, skipping")
      next
    end

    message = MorningFixturesMessage.call
    if message.nil?
      Rails.logger.info("[whatsapp:morning_digest] No matches today, skipping")
      next
    end

    WhatsappSender.call(message)
    WhatsappNotification.create!(
      notification_type: "morning_digest",
      dedupe_key: dedupe_key,
      sent_at: Time.current
    )
    Rails.logger.info("[whatsapp:morning_digest] Sent")
  rescue => e
    Rails.logger.error("[whatsapp:morning_digest] Failed: #{e.message}")
  end

  desc "Send result and leaderboard notifications for any unnotified PostEvent matches"
  task check_results: :environment do
    Match.where(status: "PostEvent")
         .includes(home_team: :groups, away_team: :groups)
         .each do |match|
      dedupe_key = "match_result:#{match.id}"

      WhatsappNotification.create!(
        notification_type: "match_result",
        match_id: match.id,
        dedupe_key: dedupe_key,
        sent_at: Time.current
      )

      WhatsappSender.call(MatchResultMessage.call(match))

      sleep 1

      WhatsappSender.call(LeaderboardSnapshotMessage.call)
      Rails.logger.info("[whatsapp:check_results] Sent result for match #{match.id}")
    rescue ActiveRecord::RecordNotUnique
      next
    rescue => e
      Rails.logger.error("[whatsapp:check_results] Failed for match #{match.id}: #{e.message}")
    end
  end
end
