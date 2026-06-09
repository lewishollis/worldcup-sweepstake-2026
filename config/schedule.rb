# Whenever schedule — generates crontab entries.
# Apply with: bundle exec whenever --update-crontab
# Remove with: bundle exec whenever --clear-crontab

set :output, Rails.root.join("log/cron.log")

every 10.minutes do
  rake "matches:sync"
end

every :day, at: "7:00 am" do
  rake "news_feed:fetch"
end

every :day, at: "10:00 pm" do
  rake "news_feed:fetch"
end
