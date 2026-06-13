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

    favourites = group_favourites(table)
    if favourites.any?
      lines << "Group favourites (strongest by world ranking): #{favourites.map { |t| "#{t.name}#{rank_suffix(t)}" }.join(', ')}."
    end

    lines << "What tonight's result does (as the table stands):"
    effects = qualification(table).effects(match)
    lines << "  If #{match.home_team.name} win: #{effect_phrase(effects[:home_win][:home])}"
    lines << "  If draw: #{effect_phrase(effects[:draw][:home])}; #{effect_phrase(effects[:draw][:away])}"
    lines << "  If #{match.away_team.name} win: #{effect_phrase(effects[:away_win][:away])}"

    [match.home_team, match.away_team].each do |team|
      run_in = remaining_group_fixtures(table, team, except: match)
      lines << "  #{team.name}'s remaining #{table.group_name} games: #{run_in.join('; ')}" if run_in.any?
    end

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

  # Describes where an outcome moves a team in the table and what it means for
  # qualification (and so for the owner). Uses the resulting position from
  # GroupQualification#effects.
  def effect_phrase(team_effect)
    team  = team_effect[:team]
    place =
      if team_effect[:position] == 1
        team_effect[:tied] ? "up among the group leaders" : "top of the group"
      else
        "#{team_effect[:tied] ? 'joint ' : ''}#{ordinal(team_effect[:position])} in the group"
      end
    # Only append a qualification note when it's a hard certainty; the common
    # "in contention" case is left implicit to avoid repeating it on every line.
    meaning =
      case team_effect[:flag]
      when :clinched_top2      then " (guaranteed top 2 — #{owner_name(team) || 'no owner'} banks +1)"
      when :cannot_finish_top2 then " (can no longer finish top 2)"
      else ""
      end
    "#{team.name} go #{place}#{meaning}"
  end

  # The two strongest teams in the group by world ranking (lowest numbers).
  # Teams without a ranking are excluded.
  def group_favourites(table, count: 2)
    table.teams.select(&:fifa_rank).sort_by(&:fifa_rank).first(count)
  end

  # A team's not-yet-played group fixtures other than `except` — the run-in —
  # as "vs Opponent (world #n) on 17 Jun", ordered by date.
  def remaining_group_fixtures(table, team, except:)
    table.matches
         .select { |m| m.status != "PostEvent" && m.id != except.id && (m.home_team_id == team.id || m.away_team_id == team.id) }
         .sort_by { |m| m.start_time || Time.at(0) }
         .map do |m|
           opponent = m.home_team_id == team.id ? m.away_team : m.home_team
           date     = m.start_time ? m.start_time.in_time_zone("Europe/London").strftime("%-d %b") : "TBC"
           "vs #{opponent.name}#{rank_suffix(opponent)} on #{date}"
         end
  end

  def owner_name(team)
    team.groups.first&.friend&.name
  end

  def ordinal(n)
    %w[0th 1st 2nd 3rd 4th].fetch(n, "#{n}th")
  end
end
