friend_data = [
  { name: "Lewis", profile_picture_url: ActionController::Base.helpers.asset_path('images-ben/Lewis.jpeg') },
  { name: "Ben", profile_picture_url: ActionController::Base.helpers.asset_path('images-ben/Ben.jpeg') },
  { name: "Aimee", profile_picture_url: ActionController::Base.helpers.asset_path('images-ben/Aimee.jpeg') },
  { name: "Claire", profile_picture_url: ActionController::Base.helpers.asset_path('images-ben/Claire.jpeg') },
  { name: "Ella", profile_picture_url: ActionController::Base.helpers.asset_path('images-ben/Ella.jpeg') },
  { name: "Emma", profile_picture_url: ActionController::Base.helpers.asset_path('images-ben/Emma.jpeg') },
  { name: "Jamie", profile_picture_url: "https://ui-avatars.com/api/?name=Jamie&size=150&background=random" },
  { name: "Matt", profile_picture_url: ActionController::Base.helpers.asset_path('images-ben/Matt.jpeg') },
  { name: "Richard", profile_picture_url: ActionController::Base.helpers.asset_path('images-ben/Richard.jpeg') },
  { name: "Sam", profile_picture_url: ActionController::Base.helpers.asset_path('images-ben/Sam.jpeg') },
  { name: "Bea", profile_picture_url: "https://ui-avatars.com/api/?name=Bea&size=150&background=random" },
  { name: "Nhien", profile_picture_url: ActionController::Base.helpers.asset_path('images-ben/Nhien.jpeg') }
]

friends = friend_data.map { |data| Friend.create!(data) }

team_data = [
  # Group 1
  { name: "Spain",          flag_url: "https://flagcdn.com/es.svg" },
  { name: "Australia",      flag_url: "https://flagcdn.com/au.svg" },
  { name: "Tunisia",        flag_url: "https://flagcdn.com/tn.svg" },
  { name: "Haiti",          flag_url: "https://flagcdn.com/ht.svg" },
  # Group 2
  { name: "France",         flag_url: "https://flagcdn.com/fr.svg" },
  { name: "IR Iran",        flag_url: "https://flagcdn.com/ir.svg" },
  { name: "South Africa",   flag_url: "https://flagcdn.com/za.svg" },
  { name: "Curaçao",        flag_url: "https://flagcdn.com/cw.svg" },
  # Group 3
  { name: "England",        flag_url: "https://flagcdn.com/gb-eng.svg" },
  { name: "Congo DR",       flag_url: "https://flagcdn.com/cd.svg" },
  { name: "Qatar",          flag_url: "https://flagcdn.com/qa.svg" },
  { name: "Jordan",         flag_url: "https://flagcdn.com/jo.svg" },
  # Group 4
  { name: "Brazil",         flag_url: "https://flagcdn.com/br.svg" },
  { name: "Senegal",        flag_url: "https://flagcdn.com/sn.svg" },
  { name: "Algeria",        flag_url: "https://flagcdn.com/dz.svg" },
  { name: "Saudi Arabia",   flag_url: "https://flagcdn.com/sa.svg" },
  # Group 5
  { name: "Argentina",      flag_url: "https://flagcdn.com/ar.svg" },
  { name: "Türkiye",        flag_url: "https://flagcdn.com/tr.svg" },
  { name: "Bosnia And Herz.", flag_url: "https://flagcdn.com/ba.svg" },
  { name: "New Zealand",    flag_url: "https://flagcdn.com/nz.svg" },
  # Group 6
  { name: "Portugal",       flag_url: "https://flagcdn.com/pt.svg" },
  { name: "Ecuador",        flag_url: "https://flagcdn.com/ec.svg" },
  { name: "Canada",         flag_url: "https://flagcdn.com/ca.svg" },
  { name: "Panama",         flag_url: "https://flagcdn.com/pa.svg" },
  # Group 7
  { name: "Germany",        flag_url: "https://flagcdn.com/de.svg" },
  { name: "Croatia",        flag_url: "https://flagcdn.com/hr.svg" },
  { name: "Paraguay",       flag_url: "https://flagcdn.com/py.svg" },
  { name: "Iraq",           flag_url: "https://flagcdn.com/iq.svg" },
  # Group 8
  { name: "Netherlands",    flag_url: "https://flagcdn.com/nl.svg" },
  { name: "Mexico",         flag_url: "https://flagcdn.com/mx.svg" },
  { name: "Scotland",       flag_url: "https://flagcdn.com/gb-sct.svg" },
  { name: "Cabo Verde",     flag_url: "https://flagcdn.com/cv.svg" },
  # Group 9
  { name: "Belgium",        flag_url: "https://flagcdn.com/be.svg" },
  { name: "Switzerland",    flag_url: "https://flagcdn.com/ch.svg" },
  { name: "Côte d'Ivoire",  flag_url: "https://flagcdn.com/ci.svg" },
  { name: "Uzbekistan",     flag_url: "https://flagcdn.com/uz.svg" },
  # Group 10
  { name: "Norway",         flag_url: "https://flagcdn.com/no.svg" },
  { name: "Uruguay",        flag_url: "https://flagcdn.com/uy.svg" },
  { name: "Czechia",        flag_url: "https://flagcdn.com/cz.svg" },
  { name: "Ghana",          flag_url: "https://flagcdn.com/gh.svg" },
  # Group 11
  { name: "Colombia",       flag_url: "https://flagcdn.com/co.svg" },
  { name: "USA",            flag_url: "https://flagcdn.com/us.svg" },
  { name: "Austria",        flag_url: "https://flagcdn.com/at.svg" },
  { name: "Korea Republic", flag_url: "https://flagcdn.com/kr.svg" },
  # Group 12
  { name: "Japan",          flag_url: "https://flagcdn.com/jp.svg" },
  { name: "Morocco",        flag_url: "https://flagcdn.com/ma.svg" },
  { name: "Sweden",         flag_url: "https://flagcdn.com/se.svg" },
  { name: "Egypt",          flag_url: "https://flagcdn.com/eg.svg" }
]

teams = team_data.map { |data| Team.create!(data) }

# Groups from the actual draw — friend assignments to be added after the sweepstake draw
groups_data = {
  "Group 1"  => ["Spain", "Australia", "Tunisia", "Haiti"],
  "Group 2"  => ["France", "IR Iran", "South Africa", "Curaçao"],
  "Group 3"  => ["England", "Congo DR", "Qatar", "Jordan"],
  "Group 4"  => ["Brazil", "Senegal", "Algeria", "Saudi Arabia"],
  "Group 5"  => ["Argentina", "Türkiye", "Bosnia And Herz.", "New Zealand"],
  "Group 6"  => ["Portugal", "Ecuador", "Canada", "Panama"],
  "Group 7"  => ["Germany", "Croatia", "Paraguay", "Iraq"],
  "Group 8"  => ["Netherlands", "Mexico", "Scotland", "Cabo Verde"],
  "Group 9"  => ["Belgium", "Switzerland", "Côte d'Ivoire", "Uzbekistan"],
  "Group 10" => ["Norway", "Uruguay", "Czechia", "Ghana"],
  "Group 11" => ["Colombia", "USA", "Austria", "Korea Republic"],
  "Group 12" => ["Japan", "Morocco", "Sweden", "Egypt"]
}

groups_data.each do |group_name, team_names|
  group = Group.create!(name: group_name)

  team_names.each do |team_name|
    team = teams.find { |t| t.name == team_name }
    group.teams << team if team
  end
end

puts "Seed data created. Groups 1-12 are set up with correct teams."
puts "Next step: assign each friend to their group after the sweepstake draw."
