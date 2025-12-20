class AiCommentaryService
  def initialize(match)
    @match = match
  end

  def generate_commentary
    return nil unless @match.status == 'MidEvent' || @match.status == 'PostEvent'

    prompt = build_prompt

    # Use Claude API (or OpenAI, Gemini, etc.)
    response = call_ai_api(prompt)

    # Cache the result
    @match.update(ai_commentary: response, ai_commentary_generated_at: Time.current)

    response
  rescue => e
    Rails.logger.error("AI Commentary generation failed: #{e.message}")
    generate_fallback_commentary
  end

  private

  def build_prompt
    context = []

    if @match.status == 'MidEvent'
      context << "This is a live World Cup match between #{@match.home_team.name} and #{@match.away_team.name}."
      context << "Current score: #{@match.home_team.name} #{@match.home_score} - #{@match.away_score} #{@match.away_team.name}"
      context << "Match time: #{@match.match_minute || 'In progress'}"

      if @match.accessible_event_summary.present?
        context << "Recent events: #{@match.accessible_event_summary}"
      end

      context << "Generate a short (1-2 sentences), exciting commentary about this match. Include predictions or tactical insights."
    else # PostEvent
      context << "This World Cup match just finished: #{@match.home_team.name} #{@match.home_score} - #{@match.away_score} #{@match.away_team.name}"
      context << "Generate a short (1-2 sentences) post-match analysis highlighting key moments or standout performances."
    end

    # Add user context if available
    if @match.home_friend_name != 'No owner' || @match.away_friend_name != 'No owner'
      context << "FYI: #{@match.home_team.name} is owned by #{@match.home_friend_name}" if @match.home_friend_name != 'No owner'
      context << "FYI: #{@match.away_team.name} is owned by #{@match.away_friend_name}" if @match.away_friend_name != 'No owner'
    end

    context.join(" ")
  end

  def call_ai_api(prompt)
    # Option 1: Claude API (Anthropic)
    call_claude_api(prompt)

    # Option 2: OpenAI
    # call_openai_api(prompt)

    # Option 3: Gemini
    # call_gemini_api(prompt)
  end

  def call_claude_api(prompt)
    require 'net/http'
    require 'json'

    uri = URI('https://api.anthropic.com/v1/messages')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request['x-api-key'] = Rails.application.credentials.dig(:anthropic, :api_key)
    request['anthropic-version'] = '2023-06-01'
    request['content-type'] = 'application/json'

    request.body = {
      model: 'claude-3-5-haiku-20241022', # Fast and cheap for this use case
      max_tokens: 150,
      messages: [
        {
          role: 'user',
          content: prompt
        }
      ]
    }.to_json

    response = http.request(request)
    result = JSON.parse(response.body)

    result.dig('content', 0, 'text') || generate_fallback_commentary
  end

  def call_openai_api(prompt)
    require 'net/http'
    require 'json'

    uri = URI('https://api.openai.com/v1/chat/completions')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request['Authorization'] = "Bearer #{Rails.application.credentials.dig(:openai, :api_key)}"
    request['Content-Type'] = 'application/json'

    request.body = {
      model: 'gpt-4o-mini', # Fast and cheap
      max_tokens: 150,
      messages: [
        {
          role: 'system',
          content: 'You are an enthusiastic sports commentator providing quick insights about World Cup matches.'
        },
        {
          role: 'user',
          content: prompt
        }
      ]
    }.to_json

    response = http.request(request)
    result = JSON.parse(response.body)

    result.dig('choices', 0, 'message', 'content') || generate_fallback_commentary
  end

  def generate_fallback_commentary
    templates = [
      "What an exciting match! Both teams are giving it their all.",
      "The tension is palpable as both sides fight for every ball.",
      "This match is shaping up to be a classic World Cup encounter!",
      "The tactical battle on the pitch is fascinating to watch."
    ]

    templates.sample
  end
end
