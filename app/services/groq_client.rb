class GroqClient
  GROQ_API_URL = "https://api.groq.com/openai/v1/chat/completions".freeze
  PRIMARY_MODEL = "openai/gpt-oss-120b".freeze
  FALLBACK_MODEL = "llama-3.3-70b-versatile".freeze

  def self.call(system_prompt:, user_message:, max_tokens: 300, model: PRIMARY_MODEL)
    new(system_prompt: system_prompt, user_message: user_message, max_tokens: max_tokens, model: model).call
  end

  def initialize(system_prompt:, user_message:, max_tokens:, model:)
    @system_prompt = system_prompt
    @user_message  = user_message
    @max_tokens    = max_tokens
    @model         = model
  end

  def call
    api_key = ENV["GROQ_API_KEY"] || Rails.application.credentials.dig(:groq, :api_key)
    return nil unless api_key

    uri = URI(GROQ_API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 15

    request = Net::HTTP::Post.new(uri.path)
    request["Authorization"] = "Bearer #{api_key}"
    request["Content-Type"]  = "application/json"
    body = {
      model:      @model,
      max_tokens: @max_tokens,
      messages:   [
        { role: "system", content: @system_prompt },
        { role: "user",   content: @user_message }
      ]
    }
    # GPT-OSS models reason before answering and will spend the whole token
    # budget on hidden reasoning unless capped. Other models 400 on this param,
    # so only send it for GPT-OSS.
    body[:reasoning_effort] = "low" if @model.start_with?("openai/gpt-oss")
    request.body = body.to_json

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error("Groq API error: #{response.code} #{response.body}")
      return try_fallback(api_key) rescue nil
    end

    JSON.parse(response.body).dig("choices", 0, "message", "content")
  rescue => e
    Rails.logger.error("Groq API call failed: #{e.message}")
    nil
  end

  private

  def try_fallback(api_key)
    return nil if @model == FALLBACK_MODEL
    self.class.call(
      system_prompt: @system_prompt,
      user_message:  @user_message,
      max_tokens:    @max_tokens,
      model:         FALLBACK_MODEL
    )
  rescue => e
    Rails.logger.error("Groq API fallback failed: #{e.message}")
    nil
  end
end
