friend_data = [
  { name: "Lewis", profile_picture_url: ActionController::Base.helpers.asset_path('images-ben/Lewis.jpeg') },
  { name: "Claire", profile_picture_url: ActionController::Base.helpers.asset_path('images-ben/Claire.jpeg') },
  { name: "Craig", profile_picture_url: ActionController::Base.helpers.asset_path('images-ben/Craig.jpeg') },
  { name: "Emma", profile_picture_url: ActionController::Base.helpers.asset_path('images-ben/Emma.jpeg') },
  { name: "Sam", profile_picture_url: ActionController::Base.helpers.asset_path('images-ben/Sam.jpeg') },
  { name: "Ella", profile_picture_url: ActionController::Base.helpers.asset_path('images-ben/Ella.jpeg') },
  { name: "Richard", profile_picture_url: ActionController::Base.helpers.asset_path('images-ben/Richard.jpeg') },
  { name: "Nhien", profile_picture_url: ActionController::Base.helpers.asset_path('images-ben/Nhien.jpeg') },
  { name: "Matt", profile_picture_url: ActionController::Base.helpers.asset_path('images-ben/Matt.jpeg') },
  { name: "Ben", profile_picture_url: ActionController::Base.helpers.asset_path('images-ben/Ben.jpeg') },
  { name: "Aimee", profile_picture_url: ActionController::Base.helpers.asset_path('images-ben/Aimee.jpeg') }
]

friends = friend_data.map { |data| Friend.create!(data) }

team_data = [
  { name: "Germany", flag_url: "https://flagcdn.com/de.svg" },
  { name: "Scotland", flag_url: "https://flagcdn.com/gb-sct.svg" },
  { name: "Hungary", flag_url: "https://flagcdn.com/hu.svg" },
  { name: "Switzerland", flag_url: "https://flagcdn.com/ch.svg" },
  { name: "Spain", flag_url: "https://flagcdn.com/es.svg" },
  { name: "Croatia", flag_url: "https://flagcdn.com/hr.svg" },
  { name: "Italy", flag_url: "https://flagcdn.com/it.svg" },
  { name: "Albania", flag_url: "https://flagcdn.com/al.svg" },
  { name: "Slovenia", flag_url: "https://flagcdn.com/si.svg" },
  { name: "Denmark", flag_url: "https://flagcdn.com/dk.svg" },
  { name: "Serbia", flag_url: "https://flagcdn.com/rs.svg" },
  { name: "England", flag_url: "https://flagcdn.com/gb-eng.svg" },
  { name: "Poland", flag_url: "https://flagcdn.com/pl.svg" },
  { name: "Netherlands", flag_url: "https://flagcdn.com/nl.svg" },
  { name: "Austria", flag_url: "https://flagcdn.com/at.svg" },
  { name: "France", flag_url: "https://flagcdn.com/fr.svg" },
  { name: "Belgium", flag_url: "https://flagcdn.com/be.svg" },
  { name: "Slovakia", flag_url: "https://flagcdn.com/sk.svg" },
  { name: "Romania", flag_url: "https://flagcdn.com/ro.svg" },
  { name: "Ukraine", flag_url: "https://flagcdn.com/ua.svg" },
  { name: "Turkey", flag_url: "https://flagcdn.com/tr.svg" },
  { name: "Georgia", flag_url: "https://flagcdn.com/ge.svg" },
  { name: "Portugal", flag_url: "https://flagcdn.com/pt.svg" },
  { name: "Czech Republic", flag_url: "https://flagcdn.com/cz.svg" }
]

teams = team_data.map { |data| Team.create!(data) }

group_details = [
  { name: "Group 1", friend: "Claire", multiplier: 3, teams: ["England", "Albania"] },
  { name: "Group 2", friend: "Richard", multiplier: 3, teams: ["France", "Poland"] },
  { name: "Group 3", friend: "Sam", multiplier: 3, teams: ["Germany", "Romania"] },
  { name: "Group 4", friend: "Matt", multiplier: 4, teams: ["Portugal", "Slovenia"] },
  { name: "Group 5", friend: "Ben", multiplier: 4, teams: ["Spain", "Switzerland"] },
  { name: "Group 6", friend: "Craig", multiplier: 4, teams: ["Italy", "Ukraine"] },
  { name: "Group 7", friend: "Nhien", multiplier: 4, teams: ["Netherlands", "Czech Republic"] },
  { name: "Group 8", friend: "Lewis", multiplier: 4, teams: ["Croatia", "Scotland", "Slovakia"] },
  { name: "Group 9", friend: "Ella", multiplier: 5, teams: ["Belgium", "Turkey"] },
  { name: "Group 10", friend: "Aimee", multiplier: 5, teams: ["Austria", "Denmark", "Georgia"] },
  { name: "Group 11", friend: "Emma", multiplier: 6, teams: ["Serbia", "Hungary"] },
]

group_details.each do |details|
  friend = friends.find { |f| f.name == details[:friend] }
  group = Group.create!(name: details[:name], multiplier: details[:multiplier], friend: friend)

  details[:teams].each do |team_name|
    team = teams.find { |t| t.name == team_name }
    group.teams << team if team
  end
end

puts "Seed data has been successfully created."
