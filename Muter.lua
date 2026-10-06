local addonName, Mute = ...;

Mute.Muter = {};
local Muter = Mute.Muter;
local L = Mute.L;

local DefaultSettings = {
	MuterSettings = {
		AddContextMenu = true,
		SpeechBubbles = true,
		HideInvites = true,
	},
	WatcherSettings = {
		Chat_Notify = false,
		PauseWatcher = false,
		UseNetwork = true,
	},
};
Mute.DefaultSettings = DefaultSettings;

local function ApplyDefaults(db, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(db[key]) ~= "table" then
				db[key] = {};
			end
			ApplyDefaults(db[key], value);
		elseif db[key] == nil then
			db[key] = value;
		end
	end
end

function Mute:InitSettings()
	if not MuteList_DB then MuteList_DB = {}; end
	if type(MuteList_DB.Settings) ~= "table" then MuteList_DB.Settings = {}; end
	ApplyDefaults(MuteList_DB.Settings, DefaultSettings);
end

function Mute:GetSetting(category, key)
	local db = MuteList_DB and MuteList_DB.Settings and MuteList_DB.Settings[category];
	if db and db[key] ~= nil then
		return db[key];
	end
	local defaults = DefaultSettings[category];
	return defaults and defaults[key];
end

function Mute:SetSetting(category, key, value)
	Mute:InitSettings();
	MuteList_DB.Settings[category] = MuteList_DB.Settings[category] or {};
	MuteList_DB.Settings[category][key] = value;
	if Mute.OnSettingChanged then
		Mute.OnSettingChanged(category, key, value);
	end
end

local function Print(text)
	local textColor = CreateColor(0.82, 0.62, 0.93):GenerateHexColor();
	local addonNameColored = WrapTextInColorCode(L["TOC_Title"], textColor);
	local addonNameJoiner = string.join(": ", addonNameColored, "%s");
	local text = string.format(addonNameJoiner, text);
	return DEFAULT_CHAT_FRAME:AddMessage(text, 1, 1, 1);
end
Mute.Print = Print;

-- MuteList_DB.mutes[name] = true
local function GetMutesDB()
	if not MuteList_DB then
		MuteList_DB = {};
	end
	if not MuteList_DB.mutes then
		MuteList_DB.mutes = {};
	end
	return MuteList_DB.mutes;
end

local function GetExceptionsDB()
	if not MuteList_DB then
		MuteList_DB = {};
	end
	if not MuteList_DB.exceptions then
		MuteList_DB.exceptions = {};
	end
	return MuteList_DB.exceptions;
end

local function FormatName(name)
	if not name or name == "" then return nil; end
	if not string.find(name, "-") then
		local realm = GetRealmName();
		if realm then
			realm = string.gsub(realm, "%s+", "");
			return name .. "-" .. realm;
		end
	end
	return name;
end

function Muter:IsException(name)
	if not name then return false; end
	local db = GetExceptionsDB();
	local formatted = FormatName(name);
	
	if db[name:lower()] then return true; end
	if formatted and db[formatted:lower()] then return true; end
	
	local shortName = string.match(name, "^([^-]+)");
	if shortName and db[shortName:lower()] then return true; end
	
	return false;
end

local function SeenEntryMutes(entry)
	if not entry then return false; end
	if entry.addon then return true; end
	if entry.guild and Muter:IsGuildExcepted(entry.guild) then return false; end
	return true;
end

function Muter:IsMuted(name)
	if not name then return false; end
	if Muter:IsException(name) then return false; end

	local db = GetMutesDB();
	if db[name] then return true; end

	local formatted = FormatName(name);
	if formatted and db[formatted] then
		return true;
	end

	local shortName = string.match(name, "^([^-]+)");
	if shortName and db[shortName] then
		return true;
	end

	if WatcherData_DB and WatcherData_DB.seen then
		local seen = WatcherData_DB.seen;
		local lowerFormatted = formatted and formatted:lower();
		if lowerFormatted and SeenEntryMutes(seen[lowerFormatted]) then return true; end
		if SeenEntryMutes(seen[name:lower()]) then return true; end
		local lowerShort = shortName and shortName:lower();
		if lowerShort and SeenEntryMutes(seen[lowerShort]) then return true; end
	end

	return false;
end

function Muter:AddMute(name)
	local formatted = FormatName(name);
	if not formatted then return; end

	local exceptions = GetExceptionsDB();
	if formatted then exceptions[formatted:lower()] = nil; end
	exceptions[name:lower()] = nil;
	local shortName = string.match(name, "^([^-]+)");
	if shortName then exceptions[shortName:lower()] = nil; end

	local db = GetMutesDB();
	db[formatted] = true;

	if Mute.OnMuteListChanged then
		Mute.OnMuteListChanged();
	end

	Print(string.format(L["Ignore_Added"], formatted));
end

function Muter:RemoveMute(name)
	local formatted = FormatName(name);
	if not formatted then return; end

	local db = GetMutesDB();
	db[formatted] = nil;
	db[name] = nil;

	local exceptions = GetExceptionsDB();
	if formatted then exceptions[formatted:lower()] = true; end
	exceptions[name:lower()] = true;

	if WatcherData_DB and WatcherData_DB.seen then
		local lowerFormatted = formatted:lower();
		WatcherData_DB.seen[lowerFormatted] = nil;
		WatcherData_DB.seen[name:lower()] = nil;
		
		local shortName = string.match(name, "^([^-]+)");
		if shortName then
			WatcherData_DB.seen[shortName:lower()] = nil;
		end
	end

	if Mute.OnMuteListChanged then
		Mute.OnMuteListChanged();
	end

	Print(string.format(L["Ignore_Removed"], formatted));
end

function Muter:ToggleMute(name)
	if Muter:IsMuted(name) then
		Muter:RemoveMute(name);
	else
		Muter:AddMute(name);
	end
end

--[[
speech bubbles don't expose their sender, so record every SAY/YELL/EMOTE message (muted or not) as it passes through the chat filter
then match visible bubbles against those records by text
a muted and an unmuted player saying the same thing is ambiguous, which is a limitation
--]]

local BUBBLE_TRACK_SECONDS = 10;
--local MAX_NAMEPLATE_DISTANCE = 150;
local BLANK_TEXT = " ";
local recentMessages = {}; -- [text] = { { muted, guid, lineID, expires }, ... }

local bubbleEvents = {
	CHAT_MSG_SAY = true,
	CHAT_MSG_YELL = true,
	CHAT_MSG_EMOTE = true,
	CHAT_MSG_PARTY = true,
	CHAT_MSG_PARTY_LEADER = true,
	CHAT_MSG_RAID = true,
	CHAT_MSG_RAID_LEADER = true,
	CHAT_MSG_INSTANCE_CHAT = true,
	CHAT_MSG_INSTANCE_CHAT_LEADER = true,
};

local function IsSecret(value)
	return issecretvalue and issecretvalue(value) or false;
end

-- MuteList_DB.guildMutes[lowerGuildName] = originalGuildName
local function GetGuildMutesDB()
	if not MuteList_DB then MuteList_DB = {}; end
	if not MuteList_DB.guildMutes then MuteList_DB.guildMutes = {}; end
	return MuteList_DB.guildMutes;
end

function Muter:IsGuildMuted(guildName)
	if not guildName then return false; end
	local db = GetGuildMutesDB();
	return db[guildName:lower()] ~= nil;
end

-- MuteList_DB.guildExceptions[lowerGuildName] = originalGuildName
local function GetGuildExceptionsDB()
	if not MuteList_DB then MuteList_DB = {}; end
	if not MuteList_DB.guildExceptions then MuteList_DB.guildExceptions = {}; end
	return MuteList_DB.guildExceptions;
end

function Muter:IsGuildExcepted(guildName)
	if type(guildName) ~= "string" or guildName == "" then return false; end
	return GetGuildExceptionsDB()[guildName:lower()] ~= nil;
end

function Muter:AddGuildException(guildName)
	if not guildName or guildName == "" then return; end
	guildName = string.gsub(guildName, "[<>]", "");
	GetGuildExceptionsDB()[guildName:lower()] = guildName;
	GetGuildMutesDB()[guildName:lower()] = nil;
	if Mute.OnMuteListChanged then Mute.OnMuteListChanged(); end
	Print((L["Guild_Exception_Added"]):format(guildName));
end

function Muter:RemoveGuildException(guildName)
	if not guildName or guildName == "" then return; end
	guildName = string.gsub(guildName, "[<>]", "");
	GetGuildExceptionsDB()[guildName:lower()] = nil;
	if Mute.OnMuteListChanged then Mute.OnMuteListChanged(); end
	Print((L["Guild_Exception_Removed"]):format(guildName));
end

function Muter:AddGuildMute(guildName)
	if not guildName or guildName == "" then return; end
	-- strip brackets
	guildName = string.gsub(guildName, "[<>]", "");
	
	local db = GetGuildMutesDB();
	db[guildName:lower()] = guildName;
	GetGuildExceptionsDB()[guildName:lower()] = nil;

	if Mute.OnMuteListChanged then
		Mute.OnMuteListChanged();
	end
	Print(string.format(L["Ignore_Added_Guild"], guildName));
end

function Muter:RemoveGuildMute(guildName)
	if not guildName or guildName == "" then return; end
	guildName = string.gsub(guildName, "[<>]", "");

	local lowerGuild = guildName:lower();
	local db = GetGuildMutesDB();
	db[lowerGuild] = nil;

	-- clean up seen list so they immediately unmute if they were only suspected due to the guild mute
	if WatcherData_DB and WatcherData_DB.seen then
		for key, entry in pairs(WatcherData_DB.seen) do
			if entry.guild and entry.guild:lower() == lowerGuild then
				entry.guildmute = nil;
				if not entry.verified and not entry.addon and not entry.reported then
					if not (Mute.IsTargetGuild and Mute.IsTargetGuild(entry.guild)) then
						WatcherData_DB.seen[key] = nil;
					end
				end
			end
		end
	end

	if Mute.OnMuteListChanged then
		Mute.OnMuteListChanged();
	end
	Print(string.format(L["Ignore_Removed_Guild"], guildName));
end

local TERM_MODES = { contains = true, word = true, contains_all = true, advanced = true };

local termEvents = {
	CHAT_MSG_CHANNEL = true,
	CHAT_MSG_SAY = true,
	CHAT_MSG_YELL = true,
	CHAT_MSG_WHISPER = true,
	CHAT_MSG_EMOTE = true,
	CHAT_MSG_PARTY = true,
	CHAT_MSG_PARTY_LEADER = true,
	CHAT_MSG_RAID = true,
	CHAT_MSG_RAID_LEADER = true,
	CHAT_MSG_RAID_WARNING = true,
	CHAT_MSG_INSTANCE_CHAT = true,
	CHAT_MSG_INSTANCE_CHAT_LEADER = true,
	CHAT_MSG_GUILD = true,
	CHAT_MSG_OFFICER = true,
	CHAT_MSG_BATTLEGROUND = true,
	CHAT_MSG_BATTLEGROUND_LEADER = true,
	CHAT_MSG_COMMUNITIES_CHANNEL = true,
};

local function GetTermsDB()
	if not MuteList_DB then MuteList_DB = {}; end
	if type(MuteList_DB.terms) ~= "table" then MuteList_DB.terms = {}; end
	return MuteList_DB.terms;
end

function Muter:GetTerms()
	return GetTermsDB();
end

-- lua only raises pattern errors when matching reaches the bad part
-- a trial string.find can't prove a pattern is safe. returns true or false
local MAX_PATTERN_LENGTH = 500;

local function ValidatePattern(p)
	local len = #p;
	if len == 0 then return false, "Term_Invalid"; end
	if len > MAX_PATTERN_LENGTH then return false, "Term_Err_Length"; end

	local i = 1;
	local ncaps = 0;
	local captureOpen = {}; -- [index] = true while unclosed, false once closed
	local stack = {};

	while i <= len do
		local c = p:sub(i, i);

		if c == "%" then
			local n = p:sub(i + 1, i + 1);
			if n == "" then return false, "Term_Err_EndsWithPercent"; end
			if n == "b" then
				if i + 3 > len then return false, "Term_Err_Balance"; end
				i = i + 4;
			elseif n == "f" then
				if p:sub(i + 2, i + 2) ~= "[" then return false, "Term_Err_Frontier"; end
				i = i + 2;
			elseif n:find("^%d$") then
				local idx = tonumber(n);
				if idx == 0 or captureOpen[idx] ~= false then return false, "Term_Err_BackRef"; end
				i = i + 2;
			else
				i = i + 2;
			end

		elseif c == "[" then
			i = i + 1;
			if p:sub(i, i) == "^" then i = i + 1; end
			repeat
				if i > len then return false, "Term_Err_UnclosedSet"; end
				local cc = p:sub(i, i);
				i = i + 1;
				if cc == "%" then
					if i > len then return false, "Term_Err_UnclosedSet"; end
					i = i + 1;
				end
			until p:sub(i, i) == "]";
			i = i + 1;

		elseif c == "(" then
			ncaps = ncaps + 1;
			if ncaps > 32 then return false, "Term_Err_TooManyCaptures"; end
			if p:sub(i + 1, i + 1) == ")" then
				captureOpen[ncaps] = false; -- position capture "()"
				i = i + 2;
			else
				captureOpen[ncaps] = true;
				stack[#stack + 1] = ncaps;
				i = i + 1;
			end

		elseif c == ")" then
			local idx = table.remove(stack);
			if not idx then return false, "Term_Err_UnmatchedParen"; end
			captureOpen[idx] = false;
			i = i + 1;

		else
			i = i + 1;
		end
	end

	if #stack > 0 then return false, "Term_Err_UnclosedParen"; end
	return true;
end

-- returns true or false
function Muter:ValidateTerm(pattern, mode)
	if type(pattern) ~= "string" then return false, "Term_Invalid"; end
	if mode == "advanced" then
		return ValidatePattern(strtrim(pattern):lower());
	end
	if #Muter:SplitTerm(pattern, mode) == 0 then
		return false, "Term_Invalid";
	end
	return true;
end

function Muter:SplitTerm(pattern, mode)
	local out = {};
	if type(pattern) ~= "string" then return out; end
	if mode == "advanced" then
		local term = strtrim(pattern):lower();
		if term ~= "" and ValidatePattern(term) then
			out[1] = term;
		end
		return out;
	end
	for part in pattern:gmatch("[^,]+") do
		local term = strtrim(part):lower();
		if term ~= "" then
			out[#out + 1] = term;
		end
	end
	return out;
end

local compiledTerms = setmetatable({}, { __mode = "k" });
local lastTermMsg, lastTermResult;
local lastTermLine;

local function TermsChanged()
	wipe(compiledTerms);
	lastTermMsg, lastTermResult = nil, nil;
	if Mute.OnTermsChanged then
		Mute.OnTermsChanged();
	end
end

local function GetAlternatives(term)
	local alts = compiledTerms[term];
	if not alts then
		alts = Muter:SplitTerm(term.pattern, term.mode);
		compiledTerms[term] = alts;
	end
	return alts;
end

local function CleanForTerms(msg)
	msg = msg:gsub("|H.-|h(.-)|h", "%1");
	msg = msg:gsub("|c%x%x%x%x%x%x%x%x", "");
	msg = msg:gsub("|r", "");
	msg = msg:gsub("|T.-|t", "");
	msg = msg:gsub("|A.-|a", "");
	return msg:lower();
end

local function IsWordByte(b)
	return b ~= nil and (b >= 128 or (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122));
end

local function FindWord(text, term)
	local init = 1;
	while true do
		local s, e = text:find(term, init, true);
		if not s then return false; end
		if not IsWordByte(text:byte(s - 1)) and not IsWordByte(text:byte(e + 1)) then
			return true;
		end
		init = s + 1;
	end
end

function Muter:MatchTerm(msg)
	if type(msg) ~= "string" or msg == "" then return nil; end
	local terms = GetTermsDB();
	if #terms == 0 then return nil; end

	if msg == lastTermMsg then return lastTermResult; end

	local text = CleanForTerms(msg);
	local result;
	for _, term in ipairs(terms) do
		if term.enabled ~= false then
			local mode = term.mode;
			local alts = GetAlternatives(term);

			if mode == "contains_all" then
				if #alts > 0 then
					local matchAll = true;
					for _, alt in ipairs(alts) do
						if not text:find(alt, 1, true) then
							matchAll = false;
							break;
						end
					end
					if matchAll then
						result = term;
						break;
					end
				end
			elseif mode == "advanced" then
				for _, alt in ipairs(alts) do
					if text:find(alt) then
						result = term;
						break;
					end
				end
			else
				local wholeWord = (mode == "word");
				for _, alt in ipairs(alts) do
					local hit;
					if wholeWord then
						hit = FindWord(text, alt);
					else
						hit = text:find(alt, 1, true) ~= nil;
					end
					if hit then
						result = term;
						break;
					end
				end
			end
			if result then break; end
		end
	end

	lastTermMsg, lastTermResult = msg, result;
	return result;
end

function Muter:IsTermFiltered(msg, sender, lineID, guid)
	if guid and not IsSecret(guid) and guid == UnitGUID("player") then return false; end
	--if sender and Muter:IsException(sender) then return false; end

	local term = Muter:MatchTerm(msg);
	if not term then return false; end

	if lineID and not IsSecret(lineID) and lineID ~= lastTermLine then
		lastTermLine = lineID;
		term.hits = (term.hits or 0) + 1;
	end
	return true;
end

function Muter:AddTerm(pattern, mode)
	if not TERM_MODES[mode] then mode = "contains"; end
	local alts = Muter:SplitTerm(pattern, mode);
	if #alts == 0 then return; end
	if mode ~= "advanced" then
		pattern = table.concat(alts, ", ");
	else
		pattern = strtrim(pattern);
	end

	local terms = GetTermsDB();
	for _, term in ipairs(terms) do
		if term.pattern == pattern and term.mode == mode then
			Print(string.format(L["Term_Exists"], pattern));
			return;
		end
	end

	terms[#terms + 1] = { pattern = pattern, mode = mode, enabled = true, hits = 0 };
	TermsChanged();
	Print(string.format(L["Term_Added"], pattern));
end

function Muter:EditTerm(term, pattern, mode)
	if not term then return; end
	if not TERM_MODES[mode] then mode = "contains"; end
	local alts = Muter:SplitTerm(pattern, mode);
	if #alts == 0 then return; end

	if mode ~= "advanced" then
		term.pattern = table.concat(alts, ", ");
	else
		term.pattern = strtrim(pattern);
	end
	term.mode = mode;
	TermsChanged();
end

function Muter:SetTermEnabled(term, enabled)
	if not term then return; end
	term.enabled = enabled and true or false;
	TermsChanged();
end

function Muter:RemoveTerm(term)
	local terms = GetTermsDB();
	for i, t in ipairs(terms) do
		if t == term then
			table.remove(terms, i);
			TermsChanged();
			Print(string.format(L["Term_Removed"], t.pattern));
			return;
		end
	end
end

function Muter:TrackBubble(msg, lineID, guid, muted)
	if type(msg) ~= "string" or msg == "" or IsSecret(msg) then return; end
	if IsSecret(lineID) then lineID = nil; end
	if IsSecret(guid) then guid = nil; end

	local list = recentMessages[msg];
	if not list then
		list = {};
		recentMessages[msg] = list;
	end

	local expires = GetTime() + BUBBLE_TRACK_SECONDS;
	for _, entry in ipairs(list) do
		if (lineID and entry.lineID == lineID) or (not lineID and entry.guid == guid and entry.muted == muted) then
			entry.expires = expires;
			return;
		end
	end

	list[#list + 1] = { muted = muted, guid = guid, lineID = lineID, expires = expires };
end

local function ShouldBlankBubble(bubble, list)
	local hasMuted, hasOther = false, false;
	for _, entry in ipairs(list) do
		if entry.muted then
			hasMuted = true;
		else
			hasOther = true;
		end
	end

	if not hasMuted then return false; end
	if not hasOther then return true; end

	return false;
end

local function ChatBubble_OnUpdate(self, elapsed)
	self.lastUpdate = (self.lastUpdate or 0) + elapsed;
	if self.lastUpdate < 0.1 then return; end
	self.lastUpdate = 0;

	if not next(recentMessages) then return; end

	if not Mute:GetSetting("MuterSettings", "SpeechBubbles") then
		wipe(recentMessages);
		return;
	end

	local now = GetTime();
	local anyMuted = false;
	for text, list in pairs(recentMessages) do
		for i = #list, 1, -1 do
			if list[i].expires < now then
				table.remove(list, i);
			elseif list[i].muted then
				anyMuted = true;
			end
		end
		if #list == 0 then
			recentMessages[text] = nil;
		end
	end

	if not anyMuted then return; end

	for _, bubble in pairs(C_ChatBubbles.GetAllChatBubbles()) do
		local holder = bubble:GetChildren();
		if holder and not holder:IsForbidden() and holder.String then
			local text = holder.String:GetText();
			if text and not IsSecret(text) then
				local list = recentMessages[text];
				if list and ShouldBlankBubble(bubble, list) then
					holder.String:SetText(BLANK_TEXT);
				end
			end
		end
	end
end

local previousOnSettingChanged = Mute.OnSettingChanged;
Mute.OnSettingChanged = function(category, key, value)
	if previousOnSettingChanged then previousOnSettingChanged(category, key, value); end
	if category == "MuterSettings" and key == "SpeechBubbles" and not value then
		wipe(recentMessages);
	end
end

local bubbleFrame = CreateFrame("Frame");
bubbleFrame:SetScript("OnUpdate", ChatBubble_OnUpdate);

local function CloseWhisperTab(senderName)
	if not senderName then return; end
	local senderLower = string.lower(senderName);
	
	ChatFrameUtil.ForEachChatFrame(function(chatFrame)
		if chatFrame.isTemporary and chatFrame.chatTarget and string.lower(chatFrame.chatTarget) == senderLower then
			FCF_Close(chatFrame);
		end
	end);
end

local function ChatFilter(self, event, msg, sender, ...)
	if IsSecret(msg) or IsSecret(sender) then
		return false, msg, sender, ...;
	end

	local _, _, _, _, _, _, _, _, lineID, guid = ...;

	local muted = (sender and Muter:IsMuted(sender)) and true or false;

	local blocked = muted;
	if not blocked and termEvents[event] and Muter:IsTermFiltered(msg, sender, lineID, guid) then
		blocked = true;
	end

	if bubbleEvents[event] and Mute:GetSetting("MuterSettings", "SpeechBubbles") then
		Muter:TrackBubble(msg, lineID, guid, blocked);
	end

	if blocked then
		if event == "CHAT_MSG_WHISPER" then
			RunNextFrame(function()
				CloseWhisperTab(sender);
			end);
		end
		return true;
	end
	return false, msg, sender, ...;
end

local inviteEventsFrame = CreateFrame("Frame");

local function HidePopup(popupName)
	StaticPopup_Hide(popupName);
	RunNextFrame(function()
		StaticPopup_Hide(popupName);
	end);
end

-- guild invite is a standalone frame shown via StaticPopupSpecial_Show, not StaticPopup
local function HideGuildInvite()
	if GuildInviteFrame and GuildInviteFrame:IsShown() then
		GuildInviteFrame:Hide();
	end
end

local function HideGroupInvite()
	StaticPopup_Hide("PARTY_INVITE");
end

local function OnInviteEvent(self, event, arg1, arg2)
	if not Mute:GetSetting("MuterSettings", "HideInvites") then return; end

	if event == "PARTY_INVITE_REQUEST" then
		local inviterName = arg1;
		if inviterName and Muter:IsMuted(inviterName) then
			DeclineGroup(); -- works on its own but popup remains so need to hide
			HideGroupInvite();
		end

	elseif event == "GUILD_INVITE_REQUEST" then
		local inviterName, guildName = arg1, arg2;
		if (inviterName and Muter:IsMuted(inviterName)) or (guildName and Muter:IsGuildMuted(guildName)) then
			DeclineGuild(); --doesn't appear to be needed, but going to use it just in case
			HideGuildInvite();
			RunNextFrame(HideGuildInvite);
		end

	elseif event == "DUEL_REQUESTED" then
		local opponentName = arg1; -- returns as "First-Last" instead of "First Last"
		local isMuted = false;
		
		if opponentName then
			isMuted = Muter:IsMuted(opponentName);

			if not isMuted and string.find(opponentName, "%-") then
				local alternateName = string.gsub(opponentName, "%-", " ");
				isMuted = Muter:IsMuted(alternateName);
			end
		end

		if isMuted then
			CancelDuel(); -- works on its own but just goes the extra step
			HidePopup("DUEL_REQUESTED"); -- pops up for like .5 sec before Cancel goes through, this hides it completely
		end

	elseif event == "TRADE_REQUEST" or event == "TRADE_SHOW" then
		local name, realm = UnitName("npc");
		local isMuted = false;

		if name then
			if realm and realm ~= "" then
				local standardName = string.format("%s-%s", name, realm);
				local foreverName = string.format("%s %s", name, realm);
				
				isMuted = Muter:IsMuted(standardName) or Muter:IsMuted(foreverName);
			else
				isMuted = Muter:IsMuted(name);
			end

			if isMuted then
				CancelTrade();
			end
		end
	end
end

function Muter:EnableInviteFilter()
	inviteEventsFrame:RegisterEvent("PARTY_INVITE_REQUEST");
	inviteEventsFrame:RegisterEvent("GUILD_INVITE_REQUEST");
	inviteEventsFrame:RegisterEvent("DUEL_REQUESTED");
	inviteEventsFrame:RegisterEvent("TRADE_REQUEST");
	inviteEventsFrame:RegisterEvent("TRADE_SHOW");
	inviteEventsFrame:SetScript("OnEvent", OnInviteEvent);
end

local chatEvents = {
	"CHAT_MSG_CHANNEL",
	"CHAT_MSG_SAY",
	"CHAT_MSG_YELL",
	"CHAT_MSG_WHISPER",
	"CHAT_MSG_EMOTE",
	"CHAT_MSG_TEXT_EMOTE",
	"CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_INSTANCE_CHAT_LEADER",
	"CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_GUILD",
	"CHAT_MSG_OFFICER",
	"CHAT_MSG_BATTLEGROUND",
	"CHAT_MSG_BATTLEGROUND_LEADER",
	"CHAT_MSG_RAID_WARNING",
	"CHAT_MSG_COMMUNITIES_CHANNEL",
};

function Muter:EnableChatFilter()
	for _, event in ipairs(chatEvents) do
		ChatFrame_AddMessageEventFilter(event, ChatFilter);
	end
end

SLASH_MUTEADDON1 = L["SLASH_CHAT_MUTE1"]; -- localized
SLASH_MUTEADDON2 = L["SLASH_CHAT_MUTE4"]; -- english
SlashCmdList["MUTEADDON"] = function(msg)
	local name = strtrim(msg);
	if name ~= "" then
		Muter:ToggleMute(name);
	else
		Print(L["MuteSlashHelp"]);
	end
end;

local frame = CreateFrame("Frame");
frame:RegisterEvent("ADDON_LOADED");
frame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		GetMutesDB();
		Mute:InitSettings();
		Muter:EnableChatFilter();
		Muter:EnableInviteFilter();
	end
end);

local chatTargets = {
	"SELF",
	"PLAYER",
	"PARTY",
	"RAID",
	"RAID_PLAYER",
	"ENEMY_PLAYER",
	"FOCUS",
	"FRIEND",
	"GUILD",
	"GUILD_OFFLINE",
	"ARENAENEMY",
	"BN_FRIEND",
	"CHAT_ROSTER",
	"COMMUNITIES_GUILD_MEMBER",
	"COMMUNITIES_WOW_MEMBER",
};

local function MutePlayerPastMessages(targetPlayerName)
	local function DoesMessageMatch(message, r, g, b, infoID, accessID, typeID, event, eventArgs, MessageFormatter, ...)
		if not eventArgs then
			return false;
		end
		
		local sender = eventArgs[2];
		
		return type(sender) == "string" and sender == targetPlayerName;
	end

	local function SetMutedMessage(message, r, g, b, infoID, accessID, typeID, event, eventArgs, MessageFormatter, ...)
		local mutedText = L["PlayerIsMuted"];
		
		return mutedText, 1, 1, 0, infoID, accessID, typeID, event, eventArgs, MessageFormatter, ...;
	end

	ChatFrameUtil.ForEachChatFrame(function(chatFrame)
		chatFrame:TransformMessages(DoesMessageMatch, SetMutedMessage);
	end)
end

for _, value in ipairs(chatTargets) do
	Menu.ModifyMenu("MENU_UNIT_" .. value, function(owner, rootDescription, contextData)
		if not Mute:GetSetting("MuterSettings", "AddContextMenu") then return; end
		local playerName = contextData.name;
		if not playerName then return; end
		
		if Muter:IsMuted(playerName) then
			rootDescription:CreateButton(L["UnmutePlayer"], function()
				Muter:RemoveMute(playerName);
			end);
		else
			rootDescription:CreateButton(L["MutePlayer"], function()
				Muter:AddMute(playerName);
				MutePlayerPastMessages(playerName);
			end);
		end
	end);
end

-- API for addons (Artificer)
local apiListeners = {};
MuteAddonAPI = {
	IsMuted = function(name)
		if type(name) ~= "string" then return false; end
		return Muter:IsMuted(name) and true or false;
	end,
	RegisterCallback = function(fn)
		if type(fn) == "function" then
			apiListeners[#apiListeners + 1] = fn;
		end
	end,
	Fire = function()
		for _, fn in ipairs(apiListeners) do
			fn();
		end
	end,
};