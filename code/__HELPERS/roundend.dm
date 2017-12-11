/datum/controller/subsystem/ticker/proc/gather_roundend_feedback()
	var/clients = GLOB.player_list.len
	var/surviving_humans = 0
	var/surviving_total = 0
	var/ghosts = 0
	var/escaped_humans = 0
	var/escaped_total = 0

	for(var/mob/M in GLOB.player_list)
		if(ishuman(M))
			if(!M.stat)
				surviving_humans++
				if(M.z == ZLEVEL_CENTCOM)
					escaped_humans++
		if(!M.stat)
			surviving_total++
			if(M.z == ZLEVEL_CENTCOM)
				escaped_total++

		if(isobserver(M))
			ghosts++

	if(clients)
		SSblackbox.record_feedback("nested tally", "round_end_stats", clients, list("clients"))
	if(ghosts)
		SSblackbox.record_feedback("nested tally", "round_end_stats", ghosts, list("ghosts"))
	if(surviving_humans)
		SSblackbox.record_feedback("nested tally", "round_end_stats", surviving_humans, list("survivors", "human"))
	if(surviving_total)
		SSblackbox.record_feedback("nested tally", "round_end_stats", surviving_total, list("survivors", "total"))
	if(escaped_humans)
		SSblackbox.record_feedback("nested tally", "round_end_stats", escaped_humans, list("escapees", "human"))
	if(escaped_total)
		SSblackbox.record_feedback("nested tally", "round_end_stats", escaped_total, list("escapees", "total"))

	gather_antag_success_rate()

/datum/controller/subsystem/ticker/proc/gather_antag_success_rate()
	var/team_gid = 1
	var/list/team_ids = list()

	for(var/datum/antagonist/A in GLOB.antagonists)
		var/list/antag_info = list()
		antag_info["key"] = A.owner.key
		antag_info["name"] = A.owner.name
		antag_info["antagonist_type"] = A.type
		antag_info["antagonist_name"] = A.name //For auto and custom roles
		antag_info["objectives"] = list()
		antag_info["team"] = list()
		var/datum/objective_team/T = A.get_team()
		if(T)
			antag_info["team"]["type"] = T.type
			antag_info["team"]["name"] = T.name
			if(!team_ids[T])
				team_ids[T] = team_gid++
			antag_info["team"]["id"] = team_ids[T]

		if(!A.owner)
			continue
		if(A.objectives.len)
			for(var/datum/objective/O in A.objectives)
				var/result = O.check_completion() ? "SUCCESS" : "FAIL"
				antag_info["objectives"] += list(list("objective_type"=O.type,"text"=O.explanation_text,"result"=result))
		SSblackbox.record_feedback("associative", "antagonists", 1, antag_info)


/datum/controller/subsystem/ticker/proc/declare_completion()
	set waitfor = FALSE

	to_chat(world, "<BR><BR><BR><FONT size=3><B>The round has ended.</B></FONT>")
	if(LAZYLEN(GLOB.round_end_notifiees))
		send2irc("Notice", "[GLOB.round_end_notifiees.Join(", ")] the round has ended.")

	for(var/client/C in GLOB.clients)
		if(!C.credits)
			C.RollCredits()
		C.playtitlemusic(40)

	display_report()

	gather_roundend_feedback()

	CHECK_TICK

	//Set news report and mode result
	mode.set_round_result()
	
	send2irc("Server", "Round just ended.")
	
	if(CONFIG_GET(string/cross_server_address))
		send_news_report()

	CHECK_TICK

	//These need update to actually reflect the real antagonists
	//Print a list of antagonists to the server log
	var/list/total_antagonists = list()
	//Look into all mobs in world, dead or alive
	for(var/datum/mind/Mind in minds)
		var/temprole = Mind.special_role
		if(temprole)							//if they are an antagonist of some sort.
			if(temprole in total_antagonists)	//If the role exists already, add the name to it
				total_antagonists[temprole] += ", [Mind.name]([Mind.key])"
			else
				total_antagonists.Add(temprole) //If the role doesnt exist in the list, create it and add the mob
				total_antagonists[temprole] += ": [Mind.name]([Mind.key])"

	CHECK_TICK

	//Now print them all into the log!
	log_game("Antagonists at round end were...")
	for(var/i in total_antagonists)
		log_game("[i]s[total_antagonists[i]].")

	CHECK_TICK

	//Collects persistence features
	if(mode.allow_persistence_save)
		SSpersistence.CollectData()

	//stop collecting feedback during grifftime
	SSblackbox.Seal()

	sleep(50)
	ready_for_reboot = TRUE
	standard_reboot()

/datum/controller/subsystem/ticker/proc/standard_reboot()
	if(ready_for_reboot)
		if(mode.station_was_nuked)
			Reboot("Station destroyed by Nuclear Device.", "nuke")
		else
			Reboot("Round ended.", "proper completion")
	else
		CRASH("Attempted standard reboot without ticker roundend completion")

//Common part of the report
/datum/controller/subsystem/ticker/proc/build_roundend_report()
	var/list/parts = list()

	//Gamemode specific things. Should be empty most of the time.
	parts += mode.special_report()

	CHECK_TICK
	
	//AI laws
	parts += law_report()
	
	CHECK_TICK

	//Antagonists
	parts += antag_report()
	
	CHECK_TICK
	//Medals
	parts += medal_report()
	//Station Goals
	parts += goal_report()

	listclearnulls(parts)

	return parts.Join()


/datum/controller/subsystem/ticker/proc/survivor_report()
	var/list/parts = list()
	var/station_evacuated = EMERGENCY_ESCAPED_OR_ENDGAMED
	var/num_survivors = 0
	var/num_escapees = 0
	var/num_shuttle_escapees = 0

	//Player status report
	for(var/i in GLOB.mob_list)
		var/mob/Player = i
		if(Player.mind && !isnewplayer(Player))
			if(Player.stat != DEAD && !isbrain(Player))
				num_survivors++
				if(station_evacuated) //If the shuttle has already left the station
					var/list/area/shuttle_areas
					if(SSshuttle && SSshuttle.emergency)
						shuttle_areas = SSshuttle.emergency.shuttle_areas
					if(Player.onCentCom() || Player.onSyndieBase())
						num_escapees++
						if(shuttle_areas[get_area(Player)])
							num_shuttle_escapees++

	//Round statistics report
	var/datum/station_state/end_state = new /datum/station_state()
	end_state.count()
	var/station_integrity = min(PERCENT(GLOB.start_state.score(end_state)), 100)

	parts += "[GLOB.TAB]Shift Duration: <B>[DisplayTimeText(world.time - SSticker.round_start_time)]</B>"
	parts += "[GLOB.TAB]Station Integrity: <B>[mode.station_was_nuked ? "<span class='redtext'>Destroyed</span>" : "[station_integrity]%"]</B>"
	var/total_players = GLOB.joined_player_list.len
	if(total_players)
		parts+= "[GLOB.TAB]Total Population: <B>[total_players]</B>"
		if(station_evacuated)
			parts += "<BR>[GLOB.TAB]Evacuation Rate: <B>[num_escapees] ([PERCENT(num_escapees/total_players)]%)</B>"
			parts += "[GLOB.TAB](on emergency shuttle): <B>[num_shuttle_escapees] ([PERCENT(num_shuttle_escapees/total_players)]%)</B>"
		parts += "[GLOB.TAB]Survival Rate: <B>[num_survivors] ([PERCENT(num_survivors/total_players)]%)</B>"
	return parts.Join("<br>")

/datum/controller/subsystem/ticker/proc/show_roundend_report(client/C,common_report)
	var/list/report_parts = list()
	
	report_parts += personal_report(C)
	report_parts += common_report

	var/datum/browser/roundend_report = new(C, "roundend")
	roundend_report.width = 800
	roundend_report.height = 600
	roundend_report.set_content(report_parts.Join())
	roundend_report.stylesheets = list()
	roundend_report.add_stylesheet("roundend",'html/browser/roundend.css')
	
	roundend_report.open(0)

/datum/controller/subsystem/ticker/proc/personal_report(client/C)
	var/list/parts = list()
	var/mob/M = C.mob
	if(M.mind && !isnewplayer(M))
		if(M.stat != DEAD && !isbrain(M))
			if(EMERGENCY_ESCAPED_OR_ENDGAMED)
				if(!M.onCentCom() || !M.onSyndieBase())
					parts += "<div class='panel stationborder'>"
					parts += "<span class='marooned'>You managed to survive, but were marooned on [station_name()]...</span>"
				else
					parts += "<div class='panel greenborder'>"
					parts += "<span class='greentext'>You managed to survive the events on [station_name()] as [M.real_name].</span>"
			else
				parts += "<div class='panel greenborder'>"
				parts += "<span class='greentext'>You managed to survive the events on [station_name()] as [M.real_name].</span>"

		else
			parts += "<div class='panel redborder'>"
			parts += "<span class='redtext'>You did not survive the events on [station_name()]...</span>"
	else
		parts += "<div class='panel stationborder'>"
	parts += "<br>"
	if(GLOB.survivor_report)
		parts += GLOB.survivor_report
	else
		parts += survivor_report()

	parts += "</div>"

	return parts.Join()

/datum/controller/subsystem/ticker/proc/display_report()
	GLOB.common_report = build_roundend_report()
	for(var/client/C in GLOB.clients)
		show_roundend_report(C,GLOB.common_report)
		give_show_report_button(C)
		CHECK_TICK

/datum/controller/subsystem/ticker/proc/law_report()
	var/list/parts = list()
	//Silicon laws report
	for (var/i in GLOB.ai_list)
		var/mob/living/silicon/ai/aiPlayer = i
		if(aiPlayer.mind)
			parts += "<b>[aiPlayer.name] (Played by: [aiPlayer.mind.key])'s laws [aiPlayer.stat != DEAD ? "at the end of the round" : "when it was deactivated"] were:</b>"
			parts += aiPlayer.laws.get_law_list(include_zeroth=TRUE)

		parts += "<b>Total law changes: [aiPlayer.law_change_counter]</b>"

		if (aiPlayer.connected_robots.len)
			var/robolist = "<b>[aiPlayer.real_name]'s minions were:</b> "
			for(var/mob/living/silicon/robot/robo in aiPlayer.connected_robots)
				if(robo.mind)
					robolist += "[robo.name][robo.stat?" (Deactivated) (Played by: [robo.mind.key]), ":" (Played by: [robo.mind.key]), "]"
			parts += "[robolist]"

	for (var/mob/living/silicon/robot/robo in GLOB.silicon_mobs)
		if (!robo.connected_ai && robo.mind)
			if (robo.stat != DEAD)
				parts += "<b>[robo.name] (Played by: [robo.mind.key]) survived as an AI-less borg! Its laws were:</b>"
			else
				parts += "<b>[robo.name] (Played by: [robo.mind.key]) was unable to survive the rigors of being a cyborg without an AI. Its laws were:</b>"

			if(robo) //How the hell do we lose robo between here and the world messages directly above this?
				parts += robo.laws.get_law_list(include_zeroth=TRUE)
	if(parts.len)
		return "<div class='panel stationborder'>[parts.Join("<br>")]</div>"
	else
		return ""

/datum/controller/subsystem/ticker/proc/goal_report()
	var/list/parts = list()
	if(mode.station_goals.len)
		for(var/V in mode.station_goals)
			var/datum/station_goal/G = V
			parts += G.get_result()
		return "<div class='panel stationborder'><ul>[parts.Join()]</ul></div>"

/datum/controller/subsystem/ticker/proc/medal_report()
	if(GLOB.commendations.len)
		var/list/parts = list()
		parts += "<span class='header'>Medal Commendations:</span>"
		for (var/com in GLOB.commendations)
			parts += com
		return "<div class='panel stationborder'>[parts.Join("<br>")]</div>"
	return ""

/datum/controller/subsystem/ticker/proc/antag_report()
	var/list/result = list()
	var/list/all_teams = list()
	var/list/all_antagonists = list()

	for(var/datum/antagonist/A in GLOB.antagonists)
		all_teams |= A.get_team()
		all_antagonists += A

	for(var/datum/objective_team/T in all_teams)
		result += T.roundend_report()
		for(var/datum/antagonist/X in all_antagonists)
			if(X.get_team() == T)
				all_antagonists -= X
		result += " "//newline between teams

	var/currrent_category
	var/datum/antagonist/previous_category

	sortTim(all_antagonists, /proc/cmp_antag_category)

	for(var/datum/antagonist/A in all_antagonists)
		if(!A.show_in_roundend)
			continue
		if(A.roundend_category != currrent_category)
			if(previous_category)
				result += previous_category.roundend_report_footer()
				result += "</div>"
			result += "<div class='panel redborder'>"
			result += A.roundend_report_header()
			currrent_category = A.roundend_category
			previous_category = A
		result += A.roundend_report()
		result += "<br>"
	
	if(all_antagonists.len)
		var/datum/antagonist/last = all_antagonists[all_antagonists.len]
		result += last.roundend_report_footer()
		result += "</div>"

	return result.Join()

/proc/cmp_antag_category(datum/antagonist/A,datum/antagonist/B)
	return sorttext(B.roundend_category,A.roundend_category)


/datum/controller/subsystem/ticker/proc/give_show_report_button(client/C)
	var/datum/action/report/R = new
	C.player_details.player_actions += R
	R.Grant(C.mob)
	to_chat(C,"<a href='?src=[REF(R)];report=1'>Show roundend report again</a>")

/datum/action/report
	name = "Show roundend report"
	button_icon_state = "vote"

/datum/action/report/Trigger()
	if(owner && GLOB.common_report && SSticker.current_state == GAME_STATE_FINISHED)
		SSticker.show_roundend_report(owner.client,GLOB.common_report)

/datum/action/report/IsAvailable()
	return 1

/datum/action/report/Topic(href,href_list)
	if(usr != owner)
		return
	if(href_list["report"])
		Trigger()
		return


/proc/printplayer(datum/mind/ply, fleecheck)
	var/text = "<b>[ply.key]</b> was <b>[ply.name]</b> the <b>[ply.assigned_role]</b> and"
	if(ply.current)
		if(ply.current.stat == DEAD)
			text += " <span class='redtext'>died</span>"
		else
			text += " <span class='greentext'>survived</span>"
		if(fleecheck)
			var/turf/T = get_turf(ply.current)
			if(!T || !(T.z in GLOB.station_z_levels))
				text += " while <span class='redtext'>fleeing the station</span>"
		if(ply.current.real_name != ply.name)
			text += " as <b>[ply.current.real_name]</b>"
	else
		text += " <span class='redtext'>had their body destroyed</span>"
	return text

/proc/printplayerlist(list/players,fleecheck)
	var/list/parts = list()

	parts += "<ul class='playerlist'>"
	for(var/datum/mind/M in players)
		parts += "<li>[printplayer(M,fleecheck)]</li>"
	parts += "</ul>"
	return parts.Join()


/proc/printobjectives(datum/mind/ply)
	var/list/objective_parts = list()
	var/count = 1
	for(var/datum/objective/objective in ply.objectives)
		if(objective.check_completion())
			objective_parts += "<b>Objective #[count]</b>: [objective.explanation_text] <span class='greentext'>Success!</span>"
		else
			objective_parts += "<b>Objective #[count]</b>: [objective.explanation_text] <span class='redtext'>Fail.</span>"
		count++
	return objective_parts.Join("<br>")