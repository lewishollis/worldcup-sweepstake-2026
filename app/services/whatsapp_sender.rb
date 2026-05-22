require "net/http"
require "uri"
require "json"

class WhatsappSender
  GRAPH_URL = "https://graph.facebook.com/v22.0"

  def self.call(message)
    new.call(message)
  end

  def call(message)
    unless credentials_present?
      Rails.logger.info("[WhatsappSender] STUB — would send: #{message}")
      return
    end

    send_message(message)
  end

  private

  def credentials_present?
    ENV["WHATSAPP_API_TOKEN"].present? &&
      ENV["WHATSAPP_PHONE_NUMBER_ID"].present? &&
      ENV["WHATSAPP_GROUP_ID"].present?
  end

  def send_message(body)
    uri = URI("#{GRAPH_URL}/#{ENV['WHATSAPP_PHONE_NUMBER_ID']}/messages")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request["Authorization"] = "Bearer #{ENV['WHATSAPP_API_TOKEN']}"
    request["Content-Type"] = "application/json"
    request.body = {
      messaging_product: "whatsapp",
      to: ENV["WHATSAPP_GROUP_ID"],
      type: "text",
      text: { body: body }
    }.to_json

    response = http.request(request)
    raise "WhatsApp API error: #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    response
  end
end
