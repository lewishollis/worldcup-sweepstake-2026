class AiLeaderboardInsightsService
  def initialize(friend)
    @friend = friend
    @analyzer = LeaderboardScenarioAnalyzer.new(friend)
  end

  def generate_personalized_insight
    analysis = @analyzer.analyze_path_to_top

    return generate_winner_message if analysis[:current_position] == 1

    # Build a prompt for the AI
    prompt = build_analysis_prompt(analysis)

    # Use AI to generate engaging commentary
    commentary = call_ai_api(prompt)

    {
      commentary: commentary,
      analysis: analysis
    }
  rescue => e
    Rails.logger.error("AI Insights generation failed: #{e.message}")
    {
      commentary: generate_fallback_insight(analysis),
      analysis: analysis
    }
  end

  private

  def build_analysis_prompt(analysis)
    prompt = []

    prompt << "You are an enthusiastic sports analyst for a World Cup sweepstake game."
    prompt << "Generate a short, personalized insight (2-3 sentences max) for #{@friend.name}."
    prompt << ""
    prompt << "Current situation:"
    prompt << "- #{@friend.name} is in #{ordinalize(analysis[:current_position])} place with #{analysis[:current_points]} points"
    prompt << "- The leader has #{analysis[:leader_points]} points"
    prompt << "- #{@friend.name} is #{analysis[:points_behind]} points behind the leader"
    prompt << ""

    if analysis[:best_scenario]
      scenario = analysis[:best_scenario]
      prompt << "Best path forward:"
      prompt << "- If #{scenario[:description]}, #{@friend.name} would move up to #{ordinalize(scenario[:new_position])} place!"
      prompt << "- This would be a #{scenario[:position_change]} position improvement"

      if scenario[:benefit_type] == :indirect
        prompt << "- Note: This isn't even #{@friend.name}'s team, but it would help them by affecting rivals' standings!"
      end
    else
      prompt << "Unfortunately, there are no upcoming matches that would immediately improve #{@friend.name}'s position."
      prompt << "They need to hope their teams win in later rounds!"
    end

    prompt << ""
    prompt << "Write an exciting, personalized message that:"
    prompt << "1. Acknowledges their current position"
    prompt << "2. Tells them what result(s) they need (be specific!)"
    prompt << "3. Adds some personality and excitement"
    prompt << ""
    prompt << "Keep it short (2-3 sentences), enthusiastic, and strategic!"

    prompt.join("\n")
  end

  def call_ai_api(prompt)
    # You can swap this for OpenAI, Gemini, etc.
    return call_with_anthropic_sdk(prompt) if anthropic_sdk_available?

    call_claude_api_http(prompt)
  end

  def anthropic_sdk_available?
    defined?(Anthropic)
  end

  def call_with_anthropic_sdk(prompt)
    client = Anthropic::Client.new(api_key: Rails.application.credentials.dig(:anthropic, :api_key))

    response = client.messages.create(
      model: 'claude-3-5-haiku-20241022',
      max_tokens: 200,
      messages: [
        { role: 'user', content: prompt }
      ]
    )

    response.dig('content', 0, 'text')
  end

  def call_claude_api_http(prompt)
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
      model: 'claude-3-5-haiku-20241022',
      max_tokens: 200,
      messages: [{ role: 'user', content: prompt }]
    }.to_json

    response = http.request(request)
    result = JSON.parse(response.body)

    result.dig('content', 0, 'text')
  end

  def generate_winner_message
    "🏆 You're in first place! Keep an eye on your rivals—they're all gunning for your spot. Hold strong!"
  end

  def generate_fallback_insight(analysis)
    if analysis[:best_scenario]
      scenario = analysis[:best_scenario]
      "You're in #{ordinalize(analysis[:current_position])} place. " \
      "Root for #{scenario[:description]} to move up to #{ordinalize(scenario[:new_position])}!"
    else
      "You're in #{ordinalize(analysis[:current_position])} place with #{analysis[:current_points]} points. " \
      "Keep watching the upcoming matches—your fortune could change!"
    end
  end

  def ordinalize(number)
    case number
    when 1 then '1st'
    when 2 then '2nd'
    when 3 then '3rd'
    else "#{number}th"
    end
  end
end
