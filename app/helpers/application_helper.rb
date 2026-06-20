module ApplicationHelper
  VIETNAM_TIME_ZONE = "Asia/Ho_Chi_Minh".freeze

  def round_to_half(number)
    (number * 2).round / 2.0
  end

  # Kick-off in Vietnam time; appends the weekday when it falls on a
  # different date to UK time (most evening matches roll past midnight)
  def vietnam_kickoff(start_time)
    return nil if start_time.blank?

    uk = start_time.in_time_zone("Europe/London")
    vn = start_time.in_time_zone(VIETNAM_TIME_ZONE)
    label = vn.strftime("%H:%M")
    label += " #{vn.strftime('%a')}" unless vn.to_date == uk.to_date
    label
  end

  def live_event_icon(type)
    { "goal" => "⚽", "yellow-card" => "🟨", "red-card" => "🟥" }.fetch(type, "•")
  end

  # Per-request map of team_id => qualification status symbol, built once from
  # every group-stage table. Returns nil for teams in no table (e.g. knockout
  # fixtures), so the badge partial simply renders nothing for them.
  def team_qualification_status(team)
    qualification_status_index[team.id]
  end

  # Methods below are private — helpers callable from views must go ABOVE this
  # line, or they will silently fail in templates with NoMethodError.
  private

  def qualification_status_index
    @qualification_status_index ||= GroupTable.all.each_with_object({}) do |table, index|
      qualification = GroupQualification.new(table)
      table.teams.each do |t|
        index[t.id] = QualificationStatus.for(t, table: table, qualification: qualification)
      end
    end
  end
end
