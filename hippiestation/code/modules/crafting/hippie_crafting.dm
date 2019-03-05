#define GRIDSIZE 9

/datum/hippie_crafting
	// List of objects inserted by the user. Each
	var/list/objects[GRIDSIZE]
	// Temp list of recipes that match the current objects and shapes inserted by the user, for quicker search everytime an object is inserted.
	var/list/possible_recipes
	// List with all recipe datums, instantiated on New().
	var/static/list/all_recipes


/datum/hippie_crafting/New()
	. = ..()
	LAZYINITLIST(all_recipes)
	LAZYINITLIST(possible_recipes)
	for(var/i in subtypesof(/datum/crafting_recipe))
		all_recipes += new i

/datum/hippie_crafting/proc/interact(mob/user)
	user << browse_rsc('hippiestation/icons/effects/arrow.png', "arrow")
	var/dat = "<style>\
			body {\
				color: #404040;\
				background-color: #bfbfbf;\
			}\
			td {\
				border: 1px solid black;\
				background-color: #8c8c8c;\
				border-color: #404040 #e6e6e6 #404040 #e6e6e6;\
				width: 50px;\
				height: 50px;\
				text-align:center;\
			}\
			td a {\
				width: 100%;\
				height: 100%;\
				display: block;\
			}\
			a{\
				text-decoration:none;\
			}</style>\
		<body><table>Crafting\n"
	for(var/i in 1 to GRIDSIZE)
		if(i%3==1) // first cell of a row, make the row
			dat += "<tr>"
		var/obj/item/I = objects[i]
		if(I)
			usr << browse_rsc(icon(I.icon, I.icon_state, I.dir), "icon_file")
			dat += "<td><a href='?src=[REF(src)];cell=[i]'><img src='icon_file'></a></td>"
		else
			dat += "<td><a href='?src=[REF(src)];cell=[i]'>&nbsp;</a></td>"
		if(i%3==0) // last cell of a row, end the row
			if(i==6) // if it's the end of the second row...ugly as fuck but hey, it probably works
				dat += "<td style='background-color:#bfbfbf;border:none;'><img src='arrow'></td>"
				var/obj/item/item = (possible_recipes.len == 1) ? possible_recipes[1].result : null
				if(item)
					usr << browse_rsc(icon(initial(item.icon), initial(item.icon_state)), "result_icon")
				dat += "<td><a href='src=[REF(src)];result=1'>[item ? "<img src='result_icon'>" : "&nbsp;"]</a></td>"
			dat += "</tr>"
	dat += "</table></body>"
	user << browse(dat,"window=Crafting;size=350x250")

/datum/hippie_crafting/Topic(href, href_list)
	to_chat(world, "1")
	var/cell = text2num(href_list["cell"])
	if(!(cell in 1 to GRIDSIZE))
		to_chat(world, "2")
		return FALSE // spoofed the href
	var/obj/item/I = usr.get_active_held_item()
	if(I)
		to_chat(world, "[I.name]")
		insert_item(I, cell)
	else if(objects[cell])
		to_chat(world, "4")
		remove_item(cell)
	check_recipe()
	interact(usr)

/datum/hippie_crafting/proc/insert_item(obj/item/part, cell)
	if(part in objects)
		var/position = objects.Find(part)
		if(position == cell)
			return // Probably a missclick, let's just do nothing
		objects[position] = null
	objects[cell] = part

/datum/hippie_crafting/proc/remove_item(cell)
	possible_recipes.Cut()
	objects[cell] = null

/datum/hippie_crafting/proc/check_recipe()
	if(!LAZYLEN(possible_recipes))
		possible_recipes = all_recipes.Copy()
	var/list/L = organized_objects()
	for(var/r in possible_recipes)
		var/datum/crafting_recipe/recipe = r
		var/list/parts = recipe.reqs.Copy()
		for(var/i in 1 to L.len)
			if(L[i])
				var/obj/item/item = L[i]
				if(recipe.shapeless)
					if(item.type in parts)
						parts -= item
					else
						possible_recipes -= recipe
						break
				else
					if(item.type != recipe.reqs[i]) // If there's an item in the grid but not in the same position in the recipe shape, remove the recipe from possible recipes
						possible_recipes -= recipe
						break
		if(recipe.shapeless && parts.len)
			possible_recipes -= recipe
	if(possible_recipes.len == 1) // If there's a single match, then we got a recipe
		return possible_recipes[1]

/datum/hippie_crafting/proc/organized_objects()
	var/list/return_list = list()
	var/found = 0
	for(var/i in objects)
		if(!i && !found)
			continue
		return_list.Add(i)
		found++
	for(var/j in found+1 to GRIDSIZE)
		return_list.Add(null)
	return return_list

/datum/hippie_recipe
	var/list/shape // List with the components required to craft the recipe. Syntax is, each row of the 3x3 grid is concatenated to have a single list with indexes representing those cells:
					// 1,2,3
					// 4,5,6
					// 7,8,9

/mob/living/carbon/human
	var/datum/hippie_crafting/hippie_crafting

/mob/living/carbon/human/Initialize()
	. = ..()
	hippie_crafting = new()

/mob/living/carbon/human/OpenCraftingMenu()
	hippie_crafting.interact(src)

/datum/crafting_recipe
	var/shapeless = TRUE // if true, the shape the reqs are placed in the grid won't matter