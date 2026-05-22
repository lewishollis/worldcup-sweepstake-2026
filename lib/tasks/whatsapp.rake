namespace :whatsapp do
  desc "Send morning fixture digest if matches exist today and not already sent"
  task morning_digest: :environment do
    dedupe_key = "morning_digest:#{Date.today}"

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
    notified_ids = WhatsappNotification.where(notification_type: "match_result").pluck(:match_id).compact

    Match.where(status: "PostEvent")
         .where.not(id: notified_ids)
         .includes(home_team: :groups, away_team: :groups)
         .each do |match|
      dedupe_key = "match_result:#{match.id}"
      next if WhatsappNotification.exists?(dedupe_key: dedupe_key)

      WhatsappSender.call(MatchResultMessage.call(match))
      WhatsappNotification.create!(
        notification_type: "match_result",
        match_id: match.id,
        dedupe_key: dedupe_key,
        sent_at: Time.current
      )

      sleep 1

      WhatsappSender.call(LeaderboardSnapshotMessage.call)
      Rails.logger.info("[whatsapp:check_results] Sent result for match #{match.id}")
    rescue => e
      Rails.logger.error("[whatsapp:check_results] Failed for match #{match.id}: #{e.message}")
    end
  end
end
