-- Floodmaker - A mod to flood undersea caverns.
-- 2018-12-15

-- Copyright (C) 2018 David G (kestral246@gmail.com)

-- Features:
-- Gives interesting areas to explore with pitch fly mode extended to swimming #7943
-- Works best with airtanks mod, wielded_light mod (under_water_shine branch), and a mese lamp.
-- Only works at sealevel or below (I've destroyed several worlds already with massive floods.)
-- The under_water_shine branch isn't stable—it's crashed several times for me.
-- Only loaded mapchunks will get flooded.  Might have to do multiple times for really big undersea caverns.
-- Little error checking, it will scan through air and water until it hits maxcount.

-- To use:
-- Only works in creative mode.  No crafting recipe.
-- Max_water_level should be set to sea level or lower, by default y=1, to avoid catastrophic flooding.
-- Point at node and right click.
-- The node clicked will turn to water, and then the flood will propagate through all
-- adjacent air and water nodes, but won't go any higher than the initial node.


local scanned = {}			-- Set containing scanned nodes, so they don't get scanned multiple times.
local tocheck = {}			-- Table of nodes to check.
local toflood = {}			-- Table of nodes that need to be flooded.
local max_water_level = 1	-- Define as sea level or lower, for safety.
local maxcount = 250000		-- Maximum number of nodes to check.

minetest.register_on_joinplayer(function(player)
	local pname = player:get_player_name()
	scanned[pname] = {}
	tocheck[pname] = {}
	toflood[pname] = {}
end)

minetest.register_on_leaveplayer(function(player)
	local pname = player:get_player_name()
	scanned[pname] = nil
	tocheck[pname] = nil
	toflood[pname] = nil
end)

-- Encode/decode xyz location into a single number to minimize memory usage of above tables.
local encode = function(pos)
	return (math.floor(pos.x + 32768) * 65536 + math.floor(pos.y + 32768)) * 65536 + math.floor(pos.z + 32768)
end

local decode = function(num)
	local pos = {}
	pos.z = (num % 65536) - 32768
	local xy = math.floor(num / 65536)
	pos.y = (xy % 65536) - 32768
	pos.x = (math.floor(xy / 65536) % 65536) - 32768
	return pos
end

-- Determine number of elements in table, for summary output.
local tlength = function(T)
	local count = 0
	for _ in pairs(T) do count = count + 1 end
	return count
end

-- Scan neighboring nodes, flag for checking if air or water.
local scan_node = function(pname, pos)
	local enc_pos = encode(pos)
	if scanned[pname][enc_pos] ~= true then  -- hasn't been scanned
		local name = minetest.get_node(pos).name
		if name == "air" or string.match(name, "water") then  -- checkable
			table.insert(tocheck[pname], enc_pos)  -- add to check list
		end
		scanned[pname][enc_pos] = true  -- don't scan again
	end
end

-- Scan overhead node, flag for checking and also return if solid cover.
local scan_up = function(pname, pos)
	local enc_pos = encode(pos)
	local name = minetest.get_node(pos).name
	local checkable = name == "air" or string.match(name, "water")
	if scanned[pname][enc_pos] ~= true then  -- hasn't been scanned
		if checkable then
			table.insert(tocheck[pname], enc_pos)  -- add to check list
		end
		scanned[pname][enc_pos] = true  -- don't scan again
	end
	return not checkable
end

-- To check, scan all neighbors and determine if this node needs to be flooded.
-- Since water propagates down, only need to flood surface nodes and covered nodes.
local check_node = function(pname, pos, ymax)
	local enc_pos = encode(pos)
	local name = minetest.get_node(pos).name
	scan_node(pname, vector.add(pos, {x=0,y=0,z=1}))  -- north
	scan_node(pname, vector.add(pos, {x=1,y=0,z=0}))  -- east
	scan_node(pname, vector.add(pos, {x=0,y=0,z=-1}))  -- south
	scan_node(pname, vector.add(pos, {x=-1,y=0,z=0}))  -- west
	scan_node(pname, vector.add(pos, {x=0,y=-1,z=0}))  -- down
	local cover = false
	if pos.y < ymax then
		cover = scan_up(pname, vector.add(pos, {x=0,y=1,z=0}))  -- up
	end
	if (cover or pos.y == ymax) and not string.match(name, "water_source") then
		table.insert(toflood[pname], enc_pos)
	end
end

minetest.register_tool("floodmaker:floodmaker", {
	description = "Floodmaker",
	inventory_image = "floodmaker.png",
	stack_max = 1,
	on_place = function(itemstack, player, pointed_thing)
		local pname = player:get_player_name()
		-- Only works in creative mode.
		if creative and creative.is_enabled_for and creative.is_enabled_for(pname) then
			-- Initialize temporary tables for safety.
			scanned[pname] = {}
			tocheck[pname] = {}
			toflood[pname] = {}
			local pos = pointed_thing.under
			-- Only works if pointing to node at or below water level.
			if pos.y <= max_water_level then
				-- Pointed to node is changed to first water source.
				minetest.set_node(pos, {name="default:water_source"})
				table.insert(tocheck[pname], encode(pos))
				check_node(pname, pos, pos.y)
				-- Check rest of nodes added during scan process.
				local count = 2
				while count <= table.getn(tocheck[pname]) and count <= maxcount do
					check_node(pname, decode(tocheck[pname][count]), pos.y)  -- fifo
					count = count + 1
				end
				-- Print statistics.
				if count == 2 then count = 1 else count = count - 2 end
				minetest.debug("floodmaker: y = "..tostring(pos.y)..", scan = "..tostring(tlength(scanned[pname]))..", check = "..tostring(count)..", flood = "..tostring(tlength(toflood[pname])+1))
				minetest.chat_send_player(pname, "floodmaker: height = "..tostring(pos.y)..", flood = "..tostring(tlength(toflood[pname])+1)..", total = "..tostring(count))
				-- Add water sources to all nodes flagged for flooding.
				for _,v in ipairs(toflood[pname]) do
					local fpos = decode(v)
					minetest.set_node(fpos, {name="default:water_source"})
				end
			else
				minetest.chat_send_player(pname, "floodmaker: height = "..tostring(pos.y)..", needs to be less than or equal to "..tostring(max_water_level))
			end
			scanned[pname] = {}  -- Clear temporary tables, which could be large.
			tocheck[pname] = {}
			toflood[pname] = {}
		end
	end,
})
