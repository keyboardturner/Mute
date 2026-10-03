local addonName, Mute = ...;
local L = Mute.L;

local PREFIX = "OLYMPUS";
local CHANNELS = { Alliance = "OlympusNet", Horde = "OlympusNetH" };
local SHOW_RAW = false;
local TARGET_GUILDS = { "olympus", "mudhutter" };
Print = Mute.Print;
local isMainline = (WOW_PROJECT_ID == 1 or WOW_PROJECT_ID == WOW_PROJECT_MAINLINE);
local isForever = (WOW_PROJECT_ID == WOW_PROJECT_CAMELOT);
local HAS_NETWORK = isForever;
Mute.HasNetwork = HAS_NETWORK;

--[[
WatcherData_DB
	.seen[normalizedName] = { name, first, last, count, types, sources, guild, verified, addon, reported }
	.guilds[lowerGuildName] = { name, first, last, total, home, senders, nsenders }

	verified
		- the game itself showed their guild (inspect, /who, invite) and that guild is one the network's own messages named from 2+ different senders
	addon
		- their own client posted on the Olympus channel (self-declared guild, but spoofable)
	reported
		- named as leader/officer/top player in someone else's census report
	suspected
		- only a guild-name substring match; may be an unrelated guild
--]]

local seen, guilds = {}, {};

local function Say(msg)
	Print(string.format(string.join(" ",L["Watcher"],"%s"),msg));
end

local function Setting(key)
	return Mute:GetSetting("WatcherSettings", key);
end

local function NetworkEnabled()
	return HAS_NETWORK and Setting("UseNetwork");
end

local function ChannelName()
	local faction = UnitFactionGroup("player");
	return CHANNELS[faction] or CHANNELS.Alliance;
end

local function Plain(s)
	return (tostring(s or ""):gsub("[|%c]", ""));
end

local function Split(s, sep)
	local out, start = {}, 1;
	while true do
		local i = s:find(sep, start, true);
		if not i then
			out[#out + 1] = s:sub(start);
			return out;
		end
		out[#out + 1] = s:sub(start, i - 1);
		start = i + #sep;
	end
end

local function LongGuild(g)
	return #g > 72 or select(2, g:gsub("[^\128-\191]", "")) > 24;
end

local function RealmField(v)
	if type(v) ~= "string" or #v > 40 or not v:find("^[^%s~|]+$") then
		return nil;
	end
	return v;
end

local function Normalize(name)
	if type(name) ~= "string" or name == "" then
		return nil;
	end
	if not name:find("-", 1, true) then
		local realm = GetNormalizedRealmName and GetNormalizedRealmName();
		if realm then
			name = name .. "-" .. realm;
		end
	end
	return name:lower();
end

local function Status(e)
	if e.verified then
		return L["Verified"];
	end
	if e.addon then
		return L["Addon"];
	end
	if e.reported then
		return L["Reported"];
	end
	if e.guildmute then
		return L["GuildMute"];
	end
	return L["Suspected"];
end
Mute.WatcherStatus = Status;

local function IsTargetGuild(guild)
	if type(guild) ~= "string" or guild == "" then return false; end
	local g = guild:lower():gsub("[%s%p]", "");
	for _, target in ipairs(TARGET_GUILDS) do
		if g:find(target, 1, true) then
			return true;
		end
	end
	return false;
end
Mute.IsTargetGuild = IsTargetGuild;

local function KnownGuild(guild)
	if not IsTargetGuild(guild) then return false; end
	local g = guild and guilds[guild:lower()];
	return g and g.nsenders >= 2;
end

local function Log(name, source, guild, flag)
	name = Plain(name);
	local key = Normalize(name);
	if not key then return; end
	local now = time();
	local e = seen[key];
	local new = not e;
	if new then
		e = { name = name, first = now, count = 0, types = {}, sources = {} };
		seen[key] = e;
	end
	e.last = now;
	e.count = (e.count or 0) + 1;
	e.sources = e.sources or {};
	e.types = e.types or {};
	e.sources[source] = true;
	if guild and guild ~= "" then
		e.guild = guild;
	end
	if flag then
		e[flag] = true;
	end
	if new then
		if Setting("Chat_Notify") then
			Say((L["NewEntry"]):format(Status(e), name, source, e.guild and (" <" .. e.guild .. ">") or ""));
		end
	end
	return e;
end

local function SeenInGuild(name, source, guild)
	if not name or not guild then return; end
	if Mute.Muter and Mute.Muter:IsGuildExcepted(guild) then return; end
	if KnownGuild(guild) then
		Log(name, source, guild, "verified");
	elseif IsTargetGuild(guild) then
		Log(name, source, guild, nil);
	elseif Mute.Muter and Mute.Muter.IsGuildMuted and Mute.Muter:IsGuildMuted(guild) then
		Log(name, source, guild, "guildmute");
	end
end

local function NoteGuild(guild, sender, info)
	guild = Plain(guild);
	if guild == "" or LongGuild(guild) then return; end
	local k = guild:lower();
	local g = guilds[k];
	if not g then
		g = { name = guild, first = time(), senders = {}, nsenders = 0 };
		guilds[k] = g;
		if Setting("Chat_Notify") then
			Say(L["NewGuild"] .. guild);
		end
	end
	g.last = time();
	local s = Normalize(sender);
	if s and not g.senders[s] then
		g.senders[s] = true;
		g.nsenders = g.nsenders + 1;
	end
	if info then
		for k2, v in pairs(info) do
			g[k2] = v;
		end
	end
end

local function Msg(key, fallback)
	local s = L[key];
	if type(s) ~= "string" or s == key then return fallback; end
	return s;
end

local joinToken = 0;

local RemoveChannel = ChatFrameUtil.RemoveChannel or ChatFrame_RemoveChannel;

local function Join()
	if not NetworkEnabled() then return; end
	if not Setting("UseNetwork") then return; end
	local name = ChannelName();
	joinToken = joinToken + 1;
	local token = joinToken;
	if (GetChannelName(name) or 0) == 0 then
		JoinChannelByName(name);
	end
	C_Timer.After(3, function()
		if RemoveChannel then
			ChatFrameUtil.ForEachChatFrame(function(cf)
				RemoveChannel(cf, name);
			end);
		end
		local id = GetChannelName(name) or 0;
		if id > 0 then
			Say(string.format(L["ListeningOnChannel"], id, name));
		elseif NetworkEnabled() and Setting("UseNetwork") then
			Say(string.format(L["CouldntJoin"], name));
		end
	end);
end

local function Leave()
	if not HAS_NETWORK then return; end
	joinToken = joinToken + 1;
	local name = ChannelName();
	if (GetChannelName(name) or 0) > 0 then
		LeaveChannelByName(name);
		Say(string.format(L["LeftChannel"], name));
	end
end

-- chunk reassembly (C<id>:<i>:<n>:<piece>)
local asm, open, bySender = {}, 0, {};

local function ClearChunks()
	wipe(asm);
	wipe(bySender);
	open = 0;
end

local previousOnSettingChanged = Mute.OnSettingChanged;
Mute.OnSettingChanged = function(category, key, value)
	if previousOnSettingChanged then previousOnSettingChanged(category, key, value); end
	if not HAS_NETWORK then return; end
	if category == "WatcherSettings" and key == "UseNetwork" then
		if value then
			Join();
		else
			Leave();
			ClearChunks();
		end
	end
end

local function CloseChunk(key)
	local e = asm[key];
	if not e then return; end
	asm[key] = nil;
	open = math.max(0, open - 1);
	local left = (bySender[e.sender] or 1) - 1;
	bySender[e.sender] = left > 0 and left or nil;
end

local function Feed(sender, msg)
	local id, i, n, body = msg:match("^C(%w+):(%d+):(%d+):(.*)$");
	if not id then return nil; end
	i, n = tonumber(i), tonumber(n);
	if n < 1 or n > 30 or i < 1 or i > n then return nil; end
	local key = sender .. "#" .. id;
	local e = asm[key];
	if not e or e.n ~= n then
		if not e then
			if (bySender[sender] or 0) >= 4 or open >= 400 then return nil; end
			bySender[sender], open = (bySender[sender] or 0) + 1, open + 1;
		end
		e = { n = n, parts = {}, got = 0, t = time(), sender = sender };
		asm[key] = e;
	end
	if not e.parts[i] then
		e.parts[i] = body;
		e.got = e.got + 1;
	end
	if e.got == n then
		CloseChunk(key);
		return table.concat(e.parts);
	end
	return nil;
end

local function GcChunks()
	local now = time();
	for k, e in pairs(asm) do
		if now - e.t > 60 then
			CloseChunk(k);
		end
	end
end
--[[
message decoding:
	R2~guild~total~online~leader~leaderOnline~users~zones~classes~levels~ranks~officers~leaderDays~inactive7~inactive30~avgLevel10~top~leaderClass~leaderLevel~leaderZone~from~home
	officers: name:online:days:class:level:zone,...
	top: name:level:class,...
]]

local function HandleReport(sender, payload)
	if #payload > 220 * 30 then return; end
	local f = Split(payload, "~");
	if (f[1] ~= "R1" and f[1] ~= "R2") or #f < 10 then return; end
	local guild = Plain(f[2]);
	if guild == "" or LongGuild(guild) then return; end

	if not IsTargetGuild(guild) then return; end
	if Mute.Muter and Mute.Muter:IsGuildExcepted(guild) then return; end

	local realm = RealmField(f[22]) or RealmField(f[21]);
	NoteGuild(guild, sender, { total = tonumber(f[3]), home = realm });

	local function add(raw, src)
		local nm = Plain(raw):sub(1, 48);
		if nm == "" then return; end
		if realm and not nm:find("-", 1, true) then
			nm = nm .. "-" .. realm;
		end
		Log(nm, src, guild, "reported");
	end
	add(f[5], L["CensusLeader"]);
	local n = 0
	for entry in (f[12] or ""):gmatch("[^,]+") do
		n = n + 1;
		if n > 30 then break; end
		add(entry:match("^([^:]+)"), L["CensusOfficer"]);
	end
	n = 0;
	for entry in (f[17] or ""):gmatch("[^,]+") do
		n = n + 1;
		if n > 5 then break; end
		add(entry:match("^([^:]+)"), L["CensusTop"]);
	end
end

local function Kind(text)
	if text:match("^C%w+:") then
		return L["ChunkCensusReport"];
	end
	return text:sub(1, 2);
end

local function OnAddonMessage(prefix, text, dist, sender)
	if not NetworkEnabled() then return; end
	if prefix ~= PREFIX or type(text) ~= "string" or type(sender) ~= "string" then return; end
	if dist ~= "CHANNEL" or #text > 255 then return; end
	if not Setting("UseNetwork") then return; end
	local kind = Kind(text);
	local tag = text:sub(1, 2);

	-- L1~map~zoneUID~rank~guild
	-- M1~tier~guild~id~class~text
	-- D1~kind~map~x~y~guild~rank~text
	local guild;
	if tag == "L1" then
		guild = text:match("^L1~%d+~%d+~%d+~(.*)$");
	elseif tag == "M1" then
		guild = text:match("^M1~%u~([^~|]+)~%d+~");
	elseif tag == "D1" then
		guild = text:match("^D1~%u+~%d+~%d+~%d+~([^~]*)~%d+~");
	end
	if guild then
		guild = Plain(guild);
		if guild == "" or LongGuild(guild) then
			guild = nil;
		end
	end

	local e = Log(sender, L["OlympusNetAddon"], guild, "addon");
	if not e then return; end
	e.types[kind] = (e.types[kind] or 0) + 1;
	if guild then
		NoteGuild(guild, sender);
	end

	if tag:sub(1, 1) == "C" then
		local payload = Feed(sender, text);
		if payload and payload:find("^R[12]~") then
			HandleReport(sender, payload);
		end
		-- "wall of shame" payloads are ignored, they list people the network has shamed
	end

	if SHOW_RAW then
		Say(sender .. " [" .. kind .. "] " .. (text:gsub("|", "||")));
	end
end

local function InspectUnit(unit)
	if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return; end
	local guildName = GetGuildInfo(unit);
	if guildName then
		SeenInGuild(GetUnitName(unit, true), L["Inspect"], guildName);
	end
end

local function ParseSystemChat(self, event, msg, ...)
	if event == "CHAT_MSG_SYSTEM" and not Setting("PauseWatcher") then
		local name, rest = msg:match("^|Hplayer:([^:|]+)|h%[[^%]]*%]|h: (.*)$");
		if name then
			local guild = rest:match("<([^<>]+)>");
			if guild then
				SeenInGuild(name, L["ManualWho"], guild);
			end
		end
	end
	return false;
end

local f = CreateFrame("Frame");
f:RegisterEvent("ADDON_LOADED");
f:RegisterEvent("PLAYER_LOGIN");
if HAS_NETWORK then
	f:RegisterEvent("CHAT_MSG_ADDON");
	f:RegisterEvent("CHAT_MSG_ADDON_LOGGED");
end
f:RegisterEvent("PLAYER_TARGET_CHANGED");
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT");
f:RegisterEvent("NAME_PLATE_UNIT_ADDED");
f:RegisterEvent("GROUP_ROSTER_UPDATE");
f:RegisterEvent("GUILD_INVITE_REQUEST");

f:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == addonName then
			WatcherData_DB = WatcherData_DB or {};
			WatcherData_DB.seen = WatcherData_DB.seen or {};
			WatcherData_DB.guilds = WatcherData_DB.guilds or {};
			seen, guilds = WatcherData_DB.seen, WatcherData_DB.guilds;
			for _, e in pairs(seen) do
				if e.confirmed then
					e.addon, e.confirmed = true, nil;
				end
			end
			for _, g in pairs(guilds) do
				g.senders = g.senders or {};
				g.nsenders = g.nsenders or 0;
			end
		end

	elseif event == "PLAYER_LOGIN" then
		if HAS_NETWORK then
			C_ChatInfo.RegisterAddonMessagePrefix(PREFIX);
			C_Timer.After(10, Join);
			C_Timer.NewTicker(60, GcChunks);
		end
		ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", ParseSystemChat);
	elseif Setting("PauseWatcher") then
		return;
	elseif event == "CHAT_MSG_ADDON" or event == "CHAT_MSG_ADDON_LOGGED" then
		OnAddonMessage(...);
	elseif event == "PLAYER_TARGET_CHANGED" then
		InspectUnit("target");
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		InspectUnit("mouseover");
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		InspectUnit((...));
	elseif event == "GROUP_ROSTER_UPDATE" then
		if IsInRaid() then
			for i = 1, GetNumGroupMembers() do
				InspectUnit("raid" .. i);
			end
		else
			for i = 1, GetNumGroupMembers() - 1 do
				InspectUnit("party" .. i);
			end
		end

	elseif event == "GUILD_INVITE_REQUEST" then
		local inviter, guildName = ...;
		SeenInGuild(inviter, L["GuildInvite"], guildName);
	end
end);