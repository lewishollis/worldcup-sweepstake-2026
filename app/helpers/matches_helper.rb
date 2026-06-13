module MatchesHelper
  # Renders the John Botson briefing as safe HTML: escapes the model's text
  # (so it can never inject markup), preserves line breaks, and bolds the
  # "Football fact:" sign-off label. Returns html_safe — only our own <strong>
  # and <br> tags are introduced; everything from the model is escaped first.
  def format_commentary(text)
    return "" if text.blank?

    escaped = ERB::Util.html_escape(text)
    escaped = escaped.gsub("Football fact:", "<strong>Football fact:</strong>")
    escaped = escaped.gsub("\n", "<br>")
    escaped.html_safe
  end
end
