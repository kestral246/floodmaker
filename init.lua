-- Floodmaker - Easily create floods—caution required!
-- 2018-12-30

-- Copyright (C) 2018 David G (kestral246@gmail.com)

local scanned = {}			-- Set containing scanned nodes, so they don't get scanned multiple times.
local tocheck = {}			-- Table of nodes to check.
local toflood = {}			-- Table of nodes that need to be flooded.
local range = {}			-- Flood radius.
local watercount = {}
local sea_level = 1	-- Define as sea level or lower, for safety.
local maxcount = 250000		-- Maximum number of nodes to check.

minetest.register_on_joinplayer(function(player)
	local pname = player:get_player_name()
	scanned[pname] = {}
	tocheck[pname] = {}
	toflood[pname] = {}
	range[pname] = 20
	watercount[pname] = 0
end)

minetest.register_on_leaveplayer(function(player)
	local pname = player:get_player_name()
	scanned[pname] = nil
	tocheck[pname] = nil
	toflood[pname] = nil
	range[pname] = nill
	watercount[pname] = nil
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

local square = function(x)
	return x * x
end

-- Scan neighboring nodes, flag for checking if air or water.
local scan_node = function(pname, pos, origin, maxdist2)
	if square(pos.x - origin.x) + square(pos.z - origin.z) <= maxdist2 then
		local enc_pos = encode(pos)
		if scanned[pname][enc_pos] ~= true then  -- hasn't been scanned
			local name = minetest.get_node(pos).name
			if name == "air" or string.match(name, "water") then  -- checkable
				table.insert(tocheck[pname], enc_pos)  -- add to check list
			end
			scanned[pname][enc_pos] = true  -- don't scan again
		end
	end
end

-- To check, scan all neighbors and determine if this node needs to be flooded.
-- Since water propagates down, only need to flood surface nodes and covered nodes.
local check_node = function(pname, pos, origin, maxdist2)
	local enc_pos = encode(pos)
	local name = minetest.get_node(pos).name
	scan_node(pname, vector.add(pos, {x=0,y=0,z=1}), origin, maxdist2)  -- north
	scan_node(pname, vector.add(pos, {x=1,y=0,z=0}), origin, maxdist2)  -- east
	scan_node(pname, vector.add(pos, {x=0,y=0,z=-1}), origin, maxdist2)  -- south
	scan_node(pname, vector.add(pos, {x=-1,y=0,z=0}), origin, maxdist2)  -- west
	scan_node(pname, vector.add(pos, {x=0,y=-1,z=0}), origin, maxdist2)  -- down
	if pos.y < origin.y then
		scan_node(pname, vector.add(pos, {x=0,y=1,z=0}), origin, maxdist2)  -- up
	end
	if not string.match(name, "water_source") then
		table.insert(toflood[pname], enc_pos)
	end
	if string.match(name, "water") then watercount[pname] = watercount[pname] + 1 end -- for statistics
end

minetest.register_tool("floodmaker:floodmaker", {
	description = "Floodmaker",
	inventory_image = "floodmaker.png",
	stack_max = 1,
	on_use = function(itemstack, player, pointed_thing)
		local pname = player:get_player_name()
		if creative and creative.is_enabled_for and creative.is_enabled_for(pname) then
			local key_stats = player:get_player_control()
			local worldedit = minetest.check_player_privs(player, "worldedit")
			if key_stats.sneak then
				-- 0, 49152, 32768, 16384, 1
				local wear = itemstack:get_wear()
				if wear == 1 then
					itemstack:set_wear(16384)
					range[pname] = 80
				elseif wear == 16384 then
					itemstack:set_wear(32768)
					range[pname] = 60
				elseif wear == 32768 then
					itemstack:set_wear(49152)
					range[pname] = 40
				else
					itemstack:set_wear(0)
					range[pname] = 20
				end
				local sr = "unlimited"
				if range[pname] <= 80 then sr = tostring(range[pname]) end
				minetest.chat_send_player(pname, "floodmaker: range set to "..sr)
				return itemstack
			end
		end
	end,
	on_place = function(itemstack, player, pointed_thing)
		local pname = player:get_player_name()
		-- Only works in creative mode.
		if creative and creative.is_enabled_for and creative.is_enabled_for(pname) then
			local key_stats = player:get_player_control()
			local worldedit = minetest.check_player_privs(player, "worldedit")
			-- Initialize temporary tables for safety.
			if key_stats.sneak and not key_stats.aux1 then  -- change range only
				local wear = itemstack:get_wear()
				if wear == 0 then
					itemstack:set_wear(49152)
					range[pname] = 40
				elseif wear == 49152 then
					itemstack:set_wear(32768)
					range[pname] = 60
				elseif wear == 32768 then
					itemstack:set_wear(16384)
					range[pname] = 80
				else
					itemstack:set_wear(1)
					range[pname] = 1000
				end
				local sr = "unlimited"
				if range[pname] <= 80 then sr = tostring(range[pname]) end
				minetest.chat_send_player(pname, "floodmaker: range set to "..sr)
				return itemstack
			else
				scanned[pname] = {}
				tocheck[pname] = {}
				toflood[pname] = {}
				watercount[pname] = 0
				local pos = vector.round(pointed_thing.under)
				local below_sea_level = pos.y <= sea_level
				-- Only works if pointing to node at or below water level.
				if below_sea_level or worldedit then
					-- Pointed to node will be changed to water.
					table.insert(tocheck[pname], encode(pos))
					local count = 1
					local range2 = range[pname] * range[pname]  -- squared
					while count <= table.getn(tocheck[pname]) and count <= maxcount do
						check_node(pname, decode(tocheck[pname][count]), pos, range2)  -- fifo
						count = count + 1
					end
					count = count - 1
					-- Test if doing actual flooding.
					if key_stats.sneak and key_stats.aux1 then
						-- Print statistics.
						minetest.chat_send_player(pname, "floodmaker: flooded "..tostring(count).." nodes, of which "..tostring(watercount[pname]).." were already water.")
						minetest.debug("floodmaker: y = "..tostring(pos.y)..", scan = "..tostring(tlength(scanned[pname]))..", check = "..tostring(count)..", flood = "..tostring(tlength(toflood[pname]))..", already H20 = "..tostring(watercount[pname]))
						-- Add water sources to all nodes flagged for flooding.
						for _,v in ipairs(toflood[pname]) do
							local fpos = decode(v)
							minetest.set_node(fpos, {name="default:water_source"})
						end
					else
						-- Print statistics.
						minetest.chat_send_player(pname, "floodmaker: would flood about "..tostring(count).." nodes, of which "..tostring(watercount[pname]).." are already water. (height = "..tostring(pos.y)..")")
						if worldedit and not below_sea_level then
							minetest.chat_send_player(pname, "Warning! ABOVE sea level! Press sneak+aux while right-clicking to flood.")
						else
							minetest.chat_send_player(pname, "Press sneak+aux while right-clicking to flood.")
						end
					end
				else  -- too high
					minetest.chat_send_player(pname, "floodmaker: height = "..tostring(pos.y)..", needs to be less than or equal to "..tostring(sea_level))
				end
				scanned[pname] = {}  -- Clear temporary tables, which could be large.
				tocheck[pname] = {}
				toflood[pname] = {}
			end
		end
	end,
})
