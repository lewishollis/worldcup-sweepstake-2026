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
  # 2022 World Cup Teams
  { name: "Qatar", flag_url: "https://flagcdn.com/qa.svg" },
  { name: "Ecuador", flag_url: "https://flagcdn.com/ec.svg" },
  { name: "Senegal", flag_url: "https://flagcdn.com/sn.svg" },
  { name: "Netherlands", flag_url: "https://flagcdn.com/nl.svg" },
  { name: "England", flag_url: "https://flagcdn.com/gb-eng.svg" },
  { name: "Iran", flag_url: "https://flagcdn.com/ir.svg" },
  { name: "United States", flag_url: "https://flagcdn.com/us.svg" },
  { name: "Wales", flag_url: "https://flagcdn.com/gb-wls.svg" },
  { name: "Argentina", flag_url: "https://flagcdn.com/ar.svg" },
  { name: "Saudi Arabia", flag_url: "https://flagcdn.com/sa.svg" },
  { name: "Mexico", flag_url: "https://flagcdn.com/mx.svg" },
  { name: "Poland", flag_url: "https://flagcdn.com/pl.svg" },
  { name: "France", flag_url: "https://flagcdn.com/fr.svg" },
  { name: "Australia", flag_url: "https://flagcdn.com/au.svg" },
  { name: "Denmark", flag_url: "https://flagcdn.com/dk.svg" },
  { name: "Tunisia", flag_url: "https://flagcdn.com/tn.svg" },
  { name: "Spain", flag_url: "https://flagcdn.com/es.svg" },
  { name: "Costa Rica", flag_url: "https://flagcdn.com/cr.svg" },
  { name: "Germany", flag_url: "https://flagcdn.com/de.svg" },
  { name: "Japan", flag_url: "https://flagcdn.com/jp.svg" },
  { name: "Belgium", flag_url: "https://flagcdn.com/be.svg" },
  { name: "Canada", flag_url: "https://flagcdn.com/ca.svg" },
  { name: "Morocco", flag_url: "https://flagcdn.com/ma.svg" },
  { name: "Croatia", flag_url: "https://flagcdn.com/hr.svg" },
  { name: "Brazil", flag_url: "https://flagcdn.com/br.svg" },
  { name: "Serbia", flag_url: "https://flagcdn.com/rs.svg" },
  { name: "Switzerland", flag_url: "https://flagcdn.com/ch.svg" },
  { name: "Cameroon", flag_url: "https://flagcdn.com/cm.svg" },
  { name: "Portugal", flag_url: "https://flagcdn.com/pt.svg" },
  { name: "Ghana", flag_url: "https://flagcdn.com/gh.svg" },
  { name: "Uruguay", flag_url: "https://flagcdn.com/uy.svg" },
  { name: "South Korea", flag_url: "https://flagcdn.com/kr.svg" }
]

teams = team_data.map { |data| Team.create!(data) }

group_details = [
  { name: "Group 1", friend: "Lewis", multiplier: 3, teams: ["Argentina", "Brazil", "France"] },
  { name: "Group 2", friend: "Claire", multiplier: 3, teams: ["Qatar", "Saudi Arabia", "Tunisia"] },
  { name: "Group 3", friend: "Craig", multiplier: 4, teams: ["England", "Portugal", "Spain"] },
  { name: "Group 4", friend: "Emma", multiplier: 4, teams: ["Ecuador", "Senegal", "Cameroon"] },
  { name: "Group 5", friend: "Sam", multiplier: 4, teams: ["Netherlands", "Croatia", "Morocco"] },
  { name: "Group 6", friend: "Ella", multiplier: 4, teams: ["United States", "Wales", "Iran"] },
  { name: "Group 7", friend: "Richard", multiplier: 5, teams: ["Germany", "Belgium", "Serbia"] },
  { name: "Group 8", friend: "Nhien", multiplier: 5, teams: ["Poland", "Denmark", "Switzerland"] },
  { name: "Group 9", friend: "Matt", multiplier: 5, teams: ["Mexico", "Costa Rica", "Canada"] },
  { name: "Group 10", friend: "Ben", multiplier: 6, teams: ["Japan", "South Korea", "Australia"] },
  { name: "Group 11", friend: "Aimee", multiplier: 6, teams: ["Uruguay", "Ghana"] },
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
