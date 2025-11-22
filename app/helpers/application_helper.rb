module ApplicationHelper
  def round_to_half(number)
    (number * 2).round / 2.0
  end
end
