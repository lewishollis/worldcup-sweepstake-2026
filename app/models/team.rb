class Team < ApplicationRecord
  # Main knockout bracket — appearing in any of these earns the +1 qualification bonus
  MAIN_KNOCKOUT_STAGES = ['Last 32', 'Last 16', 'Quarter-finals', 'Semi-finals', 'Final'].freeze
  # All knockout stages including the bronze final (used for progressed? check)
  KNOCKOUT_STAGES = (MAIN_KNOCKOUT_STAGES + ['3rd Place Final']).freeze

  # Maps BBC Sport API team names to the canonical names used in seeds/groups
  BBC_NAME_ALIASES = {
    "Iran"               => "IR Iran",
    "Bosnia-Herzegovina" => "Bosnia And Herz.",
    "Cape Verde"         => "Cabo Verde",
    "Ivory Coast"        => "Côte d'Ivoire",
    "Turkey"             => "Türkiye",
    "United States"      => "USA",
    "South Korea"        => "Korea Republic",
    "Czech Republic"     => "Czechia"
  }.freeze

  def self.canonical_name(name)
    BBC_NAME_ALIASES.fetch(name, name)
  end

  # Snapshot of the FIFA men's world ranking as of the 2026 tournament start
  # (source: published June 2026 rankings). Rankings barely move during a
  # month-long tournament, so a fixed snapshot is a reliable, factual strength
  # signal — far safer than a flaky live feed or the AI guessing from memory.
  # Keyed by the canonical team names used in seeds. Lower number = stronger.
  FIFA_RANKS = {
    "Argentina" => 1, "Spain" => 2, "France" => 3, "England" => 4, "Portugal" => 5,
    "Brazil" => 6, "Morocco" => 7, "Netherlands" => 8, "Belgium" => 9, "Germany" => 10,
    "Croatia" => 11, "Colombia" => 13, "Mexico" => 14, "Senegal" => 15, "Uruguay" => 16,
    "USA" => 17, "Japan" => 18, "Switzerland" => 19, "IR Iran" => 20, "Türkiye" => 22,
    "Ecuador" => 23, "Austria" => 24, "Korea Republic" => 25, "Australia" => 27,
    "Algeria" => 28, "Egypt" => 29, "Canada" => 30, "Norway" => 31, "Côte d'Ivoire" => 33,
    "Panama" => 34, "Sweden" => 38, "Czechia" => 40, "Paraguay" => 41, "Scotland" => 42,
    "Tunisia" => 45, "Congo DR" => 46, "Uzbekistan" => 50, "Qatar" => 56, "Iraq" => 57,
    "South Africa" => 60, "Saudi Arabia" => 61, "Jordan" => 63, "Bosnia And Herz." => 64,
    "Cabo Verde" => 67, "Ghana" => 73, "Curaçao" => 82, "Haiti" => 83, "New Zealand" => 85
  }.freeze

  has_many :home_matches, class_name: 'Match', foreign_key: 'home_team_id'
  has_many :away_matches, class_name: 'Match', foreign_key: 'away_team_id'
  has_and_belongs_to_many :groups
  has_one :friend
  has_many :friend_groups
  has_many :friends, through: :friend_groups

  def progression_score
    return 0.0 if knockout_matches.none?

    # +1 for qualifying to the main bracket — awarded as soon as a fixture there
    # exists (on qualification, not on having played). Bronze-final-only doesn't count.
    score = knockout_matches.any? { |m| MAIN_KNOCKOUT_STAGES.include?(m.stage) } ? 1.0 : 0.0

    # Per-round points come from finished games only.
    played_knockout_matches.each do |match|
      won = (match.home_team_id == id && match.winner == 'home') ||
            (match.away_team_id == id && match.winner == 'away')
      score += match.stage == '3rd Place Final' ? 0.5 : 1.0 if won
    end
    score
  end

  # Advanced to the knockouts as soon as a bracket fixture exists for them —
  # even before kick-off (PreEvent) — not only once a knockout game has finished.
  def progressed?
    knockout_matches.any?
  end

  # Used in views to query matches for display. Callers should not use this
  # for scoring — use progression_score instead.
  def matches
    Match.where("home_team_id = :team_id OR away_team_id = :team_id", team_id: id)
  end

  private

  # All knockout-stage matches involving this team, any status — a fixture
  # existing means they've been drawn into the bracket (i.e. advanced).
  def knockout_matches
    # Do not memoize: reload does not clear instance variables, so caching here
    # would return stale results after a reload call.
    all_matches = home_matches.to_a + away_matches.to_a
    all_matches.select { |m| KNOCKOUT_STAGES.include?(m.stage) }
  end

  # Finished knockout matches only — scoring counts results, not fixtures.
  def played_knockout_matches
    knockout_matches.select { |m| m.status == 'PostEvent' }
  end
end
