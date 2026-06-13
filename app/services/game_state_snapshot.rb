# Single factual source of truth for AI commentary. Assembles the leaderboard,
# group tables with safe qualification flags, team ownership, and what an
# upcoming result means for the owner. AI services consume text slices from here
# instead of hand-assembling world-state, which keeps the facts identical across
# every voice and stops the model dragging in teams that aren't in the fixture.
class GameStateSnapshot
  FLAG_LABELS = {
    clinched_top2:      "GUARANTEED top 2",
    cannot_finish_top2: "CANNOT finish top 2",
    in_contention:      "still in contention"
  }.freeze

  # Hash of group-stage results; folded into AI cache keys so a new group result
  # invalidates stale commentary (group results never change leaderboard points,
  # so the existing points-based cache keys would otherwise miss them).
  def self.data_version
    signature = Match.where(stage: "Group Stage")
                     .order(:match_id)
                     .pluck(:match_id, :status, :home_score, :away_score, :group_name)
                     .to_s
    Digest::SHA256.hexdigest(signature)[0, 16]
  end

  def initialize
    @tables       = GroupTable.all
    @table_by_id  = {} # team_id => GroupTable
    @tables.each { |t| t.teams.each { |team| @table_by_id[team.id] = t } }
    @qual_cache   = {}
  end

  attr_reader :tables
  alias group_tables tables

  def leaderboard_text
    TournamentContextService.new.leaderboard_text
  end

  # Factual group context for ONE group-stage match. Returns nil for knockouts
  # or when the match's group is unknown (e.g. pre-backfill).
  def group_context_text(match)
    return nil unless match.stage == "Group Stage"

    table = @table_by_id[match.home_team_id]
    # Defensive: only render context when the resolved table is genuinely this
    # match's group. Avoids ever showing the wrong group's table if a team's
    # matches were ever associated with more than one group_name.
    return nil unless table && table.group_name == match.group_name

    lines = ["#{table.group_name}: #{match.home_team.name} vs #{match.away_team.name} is a #{table.group_name} match.",
             "Current #{table.group_name} table (counts completed matches only):"]
    table.rows.each do |row|
      flag = FLAG_LABELS.fetch(qualification(table).flag(row.team))
      lines << "  #{row.position}. #{row.team.name}#{rank_suffix(row.team)} #{row.points}pts (GD #{format('%+d', row.gd)}) — #{flag} — owned by #{owner_name(row.team) || 'unowned'}"
    end

    table.in_progress.each do |m|
      lines << "  (in progress: #{m.home_team.name} vs #{m.away_team.name} — not yet counted)"
    end

    lines << "What this match means:"
    effects = qualification(table).effects(match)
    lines << "  If #{match.home_team.name} win: #{effect_phrase(effects[:home_win][:home], match.home_team)}"
    lines << "  If draw: #{effect_phrase(effects[:draw][:home], match.home_team)}; #{effect_phrase(effects[:draw][:away], match.away_team)}"
    lines << "  If #{match.away_team.name} win: #{effect_phrase(effects[:away_win][:away], match.away_team)}"
    lines << "Reminder: group games award no points directly. Reaching the knockouts — top 2, or one of the best third-placed teams — is where the owner's points begin (+1 for qualifying), with more points for each knockout win."
    lines.join("\n")
  end

  # One factual line about a team's group situation, for the per-friend insight.
  # Includes world ranks (the team's and its group rivals') so the AI can judge
  # how strong the team is and how kind or tough its group is — strictly from the
  # provided numbers, never from outside knowledge.
  def team_group_summary(team)
    table = @table_by_id[team.id]
    return nil unless table

    row    = table.rows.find { |r| r.team.id == team.id }
    flag   = FLAG_LABELS.fetch(qualification(table).flag(team))
    rivals = table.rows.reject { |r| r.team.id == team.id }
                  .map { |r| "#{r.team.name}#{rank_suffix(r.team)}" }.join(", ")
    summary = "#{team.name}#{rank_suffix(team)} are #{ordinal(row.position)} in #{table.group_name} on #{row.points}pts — #{flag}."
    summary += " Group rivals: #{rivals}." if rivals.present?
    summary
  end

  private

  # " (world #5)" when a FIFA ranking snapshot is available, else "". Lower is
  # stronger. The AI uses these to talk about strength/likelihood factually.
  def rank_suffix(team)
    team.fifa_rank ? " (world ##{team.fifa_rank})" : ""
  end

  def qualification(table)
    @qual_cache[table.group_name] ||= GroupQualification.new(table)
  end

  def effect_phrase(team_effect, team)
    case team_effect[:flag]
    when :clinched_top2      then "#{team.name} would be guaranteed top 2 → #{owner_name(team) || 'no owner'} banks +1 and stays live for knockout points"
    when :cannot_finish_top2 then "#{team.name} could not finish top 2, and would need to be among the best third-placed teams to reach the knockouts"
    else "#{team.name} stay in contention but are not yet safe"
    end
  end

  def owner_name(team)
    team.groups.first&.friend&.name
  end

  def ordinal(n)
    %w[0th 1st 2nd 3rd 4th].fetch(n, "#{n}th")
  end
end
