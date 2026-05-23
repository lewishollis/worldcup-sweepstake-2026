class Rack::Attack
  # Throttle game score submissions: 10 per minute per IP
  throttle("game_scores/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.path == "/game/scores" && req.post?
  end

  # General throttle: 300 requests per 5 minutes per IP
  throttle("req/ip", limit: 300, period: 5.minutes) do |req|
    req.ip
  end
end
