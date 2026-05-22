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
  # Group A
  { name: "Mexico", flag_url: "https://flagcdn.com/mx.svg" },
  { name: "South Africa", flag_url: "https://flagcdn.com/za.svg" },
  { name: "South Korea", flag_url: "https://flagcdn.com/kr.svg" },
  { name: "Czech Republic", flag_url: "https://flagcdn.com/cz.svg" },
  # Group B
  { name: "Canada", flag_url: "https://flagcdn.com/ca.svg" },
  { name: "Bosnia-Herzegovina", flag_url: "https://flagcdn.com/ba.svg" },
  { name: "Qatar", flag_url: "https://flagcdn.com/qa.svg" },
  { name: "Switzerland", flag_url: "https://flagcdn.com/ch.svg" },
  # Group C
  { name: "Brazil", flag_url: "https://flagcdn.com/br.svg" },
  { name: "Morocco", flag_url: "https://flagcdn.com/ma.svg" },
  { name: "Haiti", flag_url: "https://flagcdn.com/ht.svg" },
  { name: "Scotland", flag_url: "https://flagcdn.com/gb-sct.svg" },
  # Group D
  { name: "United States", flag_url: "https://flagcdn.com/us.svg" },
  { name: "Paraguay", flag_url: "https://flagcdn.com/py.svg" },
  { name: "Australia", flag_url: "https://flagcdn.com/au.svg" },
  { name: "Turkey", flag_url: "https://flagcdn.com/tr.svg" },
  # Group E
  { name: "Germany", flag_url: "https://flagcdn.com/de.svg" },
  { name: "Curaçao", flag_url: "https://flagcdn.com/cw.svg" },
  { name: "Ivory Coast", flag_url: "https://flagcdn.com/ci.svg" },
  { name: "Ecuador", flag_url: "https://flagcdn.com/ec.svg" },
  # Group F
  { name: "Netherlands", flag_url: "https://flagcdn.com/nl.svg" },
  { name: "Japan", flag_url: "https://flagcdn.com/jp.svg" },
  { name: "Sweden", flag_url: "https://flagcdn.com/se.svg" },
  { name: "Tunisia", flag_url: "https://flagcdn.com/tn.svg" },
  # Group G
  { name: "Belgium", flag_url: "https://flagcdn.com/be.svg" },
  { name: "Egypt", flag_url: "https://flagcdn.com/eg.svg" },
  { name: "Iran", flag_url: "https://flagcdn.com/ir.svg" },
  { name: "New Zealand", flag_url: "https://flagcdn.com/nz.svg" },
  # Group H
  { name: "Spain", flag_url: "https://flagcdn.com/es.svg" },
  { name: "Cape Verde", flag_url: "https://flagcdn.com/cv.svg" },
  { name: "Saudi Arabia", flag_url: "https://flagcdn.com/sa.svg" },
  { name: "Uruguay", flag_url: "https://flagcdn.com/uy.svg" },
  # Group I
  { name: "France", flag_url: "https://flagcdn.com/fr.svg" },
  { name: "Senegal", flag_url: "https://flagcdn.com/sn.svg" },
  { name: "Iraq", flag_url: "https://flagcdn.com/iq.svg" },
  { name: "Norway", flag_url: "https://flagcdn.com/no.svg" },
  # Group J
  { name: "Argentina", flag_url: "https://flagcdn.com/ar.svg" },
  { name: "Algeria", flag_url: "https://flagcdn.com/dz.svg" },
  { name: "Austria", flag_url: "https://flagcdn.com/at.svg" },
  { name: "Jordan", flag_url: "https://flagcdn.com/jo.svg" },
  # Group K
  { name: "Portugal", flag_url: "https://flagcdn.com/pt.svg" },
  { name: "Congo DR", flag_url: "https://flagcdn.com/cd.svg" },
  { name: "Colombia", flag_url: "https://flagcdn.com/co.svg" },
  { name: "Uzbekistan", flag_url: "https://flagcdn.com/uz.svg" },
  # Group L
  { name: "England", flag_url: "https://flagcdn.com/gb-eng.svg" },
  { name: "Croatia", flag_url: "https://flagcdn.com/hr.svg" },
  { name: "Ghana", flag_url: "https://flagcdn.com/gh.svg" },
  { name: "Panama", flag_url: "https://flagcdn.com/pa.svg" }
]

teams = team_data.map { |data| Team.create!(data) }

# Group assignments are randomised — update after the actual draw
groups_by_letter = {
  "A" => ["Mexico", "South Africa", "South Korea", "Czech Republic"],
  "B" => ["Canada", "Bosnia-Herzegovina", "Qatar", "Switzerland"],
  "C" => ["Brazil", "Morocco", "Haiti", "Scotland"],
  "D" => ["United States", "Paraguay", "Australia", "Turkey"],
  "E" => ["Germany", "Curaçao", "Ivory Coast", "Ecuador"],
  "F" => ["Netherlands", "Japan", "Sweden", "Tunisia"],
  "G" => ["Belgium", "Egypt", "Iran", "New Zealand"],
  "H" => ["Spain", "Cape Verde", "Saudi Arabia", "Uruguay"],
  "I" => ["France", "Senegal", "Iraq", "Norway"],
  "J" => ["Argentina", "Algeria", "Austria", "Jordan"],
  "K" => ["Portugal", "Congo DR", "Colombia", "Uzbekistan"],
  "L" => ["England", "Croatia", "Ghana", "Panama"]
}

shuffled_friends = friends.shuffle

groups_by_letter.each_with_index do |(letter, team_names), index|
  friend = shuffled_friends[index]
  group = Group.create!(name: "Group #{letter}", multiplier: 3, friend: friend)

  team_names.each do |team_name|
    team = teams.find { |t| t.name == team_name }
    group.teams << team if team
  end
end

puts "Seed data has been successfully created."
