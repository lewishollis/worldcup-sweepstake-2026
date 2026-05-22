# Whenever schedule — generates crontab entries.
# Apply with: bundle exec whenever --update-crontab
# Remove with: bundle exec whenever --clear-crontab

set :output, Rails.root.join("log/cron.log")

every :day, at: "8:00 am" do
  rake "whatsapp:morning_digest"
end

every 15.minutes do
  rake "whatsapp:check_results"
end
