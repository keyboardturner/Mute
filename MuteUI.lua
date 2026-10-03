local addonName, Mute = ...;
local L = Mute.L;

local ROW_HEIGHT = 20;
local TITLE = L["MuteList"];

local views = {};
local selectedKey;
local expandedNodes = {};
local nodeGuildNames = {};

local function SortByName(a, b)
	return a.name:lower() < b.name:lower();
end

local function BuildData()
	local dataProvider = CreateDataProvider();
	local existing, total = {}, 0;

	local exceptions = MuteList_DB and MuteList_DB.exceptions or {};
	local function IsExcepted(name)
		if not name then return false; end
		local nLower = name:lower()
		if exceptions[nLower] then return true; end
		local shortName = string.match(nLower, "^([^-]+)");
		if shortName and exceptions[shortName] then return true; end
		return false;
	end

	local manual, manualLower = {}, {};
	local mutes = MuteList_DB and MuteList_DB.mutes;
	if mutes then
		for name, isMuted in pairs(mutes) do
			if isMuted then
				manual[#manual + 1] = { key = name, name = name };
				manualLower[name:lower()] = true;
			end
		end
	end
	table.sort(manual, SortByName);

	local guildNodes = {};
	local sortedGuilds = {};
	local guildMutes = MuteList_DB and MuteList_DB.guildMutes;
	if guildMutes then
		for gName, originalName in pairs(guildMutes) do
			local display = (type(originalName) == "string" and originalName) or gName;
			local node = { key = "GUILD:" .. gName, name = "<" .. display .. ">", isGuild = true, rawGuild = gName, children = {} };
			guildNodes[gName] = node;
			sortedGuilds[#sortedGuilds + 1] = node;
		end
	end

	wipe(nodeGuildNames);
	local exceptionNodes, sortedExceptionGuilds = {}, {};
	local guildExceptions = MuteList_DB and MuteList_DB.guildExceptions;
	if guildExceptions then
		for gName, originalName in pairs(guildExceptions) do
			local display = (type(originalName) == "string" and originalName) or gName;
			local node = { key = "GUILDEXC:" .. gName, name = "<" .. display .. ">", isGuild = true, isExceptionGuild = true, children = {} };
			nodeGuildNames[node.key] = display;
			exceptionNodes[gName] = node;
			sortedExceptionGuilds[#sortedExceptionGuilds + 1] = node;
		end
	end

	local watcherGuildNodes = {};
	local sortedWatcherGuilds = {};
	local unknownWatcher = { key = "WATCHER_GUILD_UNKNOWN", name = "OlympusNet", isGuild = true, isWatcherGuild = true, children = {} };
	local watcherPlayerCount = 0;
	local seen = WatcherData_DB and WatcherData_DB.seen;
	if seen then
		for key, entry in pairs(seen) do
			if not manualLower[key] then
				local isExcepted = IsExcepted(key);
				local name = (type(entry) == "table" and entry.name) or key;
				local gName = (type(entry) == "table" and entry.guild) or nil;
				local lowerGuild = gName and gName:lower();
				
				if lowerGuild and guildNodes[lowerGuild] then
					local gNode = guildNodes[lowerGuild];
					gNode.children[#gNode.children + 1] = { key = key, name = name, entry = entry, mutedByGuild = gName, isExcepted = isExcepted };
				elseif lowerGuild and exceptionNodes[lowerGuild] and not (type(entry) == "table" and entry.addon) then
					local xNode = exceptionNodes[lowerGuild];
					xNode.children[#xNode.children + 1] = { key = key, name = name, entry = entry, exceptedByGuild = gName };
				elseif not isExcepted then
					watcherPlayerCount = watcherPlayerCount + 1;
					if gName and gName ~= "" then
						if not watcherGuildNodes[lowerGuild] then
							local gNode = { key = "WATCHER_GUILD:" .. lowerGuild, name = "<" .. gName .. ">", isGuild = true, isWatcherGuild = true, children = {} };
							nodeGuildNames[gNode.key] = gName;
							watcherGuildNodes[lowerGuild] = gNode;
							sortedWatcherGuilds[#sortedWatcherGuilds + 1] = gNode;
						end
						table.insert(watcherGuildNodes[lowerGuild].children, { key = key, name = name, entry = entry, isWatcherChild = true });
					else
						table.insert(unknownWatcher.children, { key = key, name = name, entry = entry, isWatcherChild = true });
					end
				end
			end
		end
	end
	
	table.sort(sortedGuilds, SortByName);
	table.sort(sortedWatcherGuilds, SortByName);

	if #manual > 0 then
		dataProvider:Insert({ header = true, text = string.format(L["MutedPlayers_Header"], #manual), key = "CAT_MANUAL" });
		if expandedNodes["CAT_MANUAL"] ~= false then
			for _, row in ipairs(manual) do
				existing[row.key] = true;
				dataProvider:Insert(row);
			end
		end
	end

	if #sortedGuilds > 0 then
		dataProvider:Insert({ header = true, text = string.format(L["MutedGuilds_Header"], #sortedGuilds), key = "CAT_GUILDS" });
		if expandedNodes["CAT_GUILDS"] ~= false then
			for _, gNode in ipairs(sortedGuilds) do
				existing[gNode.key] = true;
				dataProvider:Insert(gNode);
				
				if expandedNodes[gNode.key] then
					table.sort(gNode.children, SortByName);
					for _, child in ipairs(gNode.children) do
						existing[child.key] = true;
						dataProvider:Insert(child);
					end
				end
			end
		end
	end

	if #sortedExceptionGuilds > 0 then
		dataProvider:Insert({ header = true, text = string.format(L["ExceptedGuilds_Header"], #sortedExceptionGuilds), key = "CAT_GUILDEXC" });
		if expandedNodes["CAT_GUILDEXC"] ~= false then
			table.sort(sortedExceptionGuilds, SortByName);
			for _, xNode in ipairs(sortedExceptionGuilds) do
				existing[xNode.key] = true;
				dataProvider:Insert(xNode);
				if expandedNodes[xNode.key] then
					table.sort(xNode.children, SortByName);
					for _, child in ipairs(xNode.children) do
						existing[child.key] = true;
						dataProvider:Insert(child);
					end
				end
			end
		end
	end

	if watcherPlayerCount > 0 then
		dataProvider:Insert({ header = true, text = string.format(L["Watchlist_Header"], watcherPlayerCount), key = "CAT_WATCHER" });
		if expandedNodes["CAT_WATCHER"] ~= false then
			for _, gNode in ipairs(sortedWatcherGuilds) do
				existing[gNode.key] = true;
				dataProvider:Insert(gNode);
				if expandedNodes[gNode.key] then
					table.sort(gNode.children, SortByName);
					for _, child in ipairs(gNode.children) do
						existing[child.key] = true;
						dataProvider:Insert(child);
					end
				end
			end
			
			if #unknownWatcher.children > 0 then
				existing[unknownWatcher.key] = true;
				dataProvider:Insert(unknownWatcher);
				if expandedNodes[unknownWatcher.key] then
					table.sort(unknownWatcher.children, SortByName);
					for _, child in ipairs(unknownWatcher.children) do
						existing[child.key] = true;
						dataProvider:Insert(child);
					end
				end
			end
		end
	end

	total = #manual + #sortedGuilds + watcherPlayerCount;
	return dataProvider, existing, total;
end

local function UpdateRowSelection(row)
	if row and row.Selected then
		row.Selected:SetShown(row.data ~= nil and row.data.key == selectedKey);
	end
end

local function UpdateSelection()
	for _, view in ipairs(views) do
		if view.scrollBox then
			view.scrollBox:ForEachFrame(UpdateRowSelection);
		end
		if view.unmuteButton then
			view.unmuteButton:SetEnabled(selectedKey ~= nil);
		end
	end
end

local function Row_OnClick(self)
	if not self.data then return; end
	if selectedKey == self.data.key then
		selectedKey = nil;
	else
		selectedKey = self.data.key;
	end
	UpdateSelection();
end

local function Row_OnEnter(self)
	local data = self.data;
	if not data then return; end

	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(data.name, 1, 1, 1);

	if data.isGuild then
		if data.isWatcherGuild then
			GameTooltip:AddLine(L["WatcherGuild"], 0.7, 0.7, 0.7);
			GameTooltip:AddLine(string.format(L["SeenPlayersNumber"], #(data.children or {})), 0.7, 0.7, 0.7);
		elseif data.isExceptionGuild then
			GameTooltip:AddLine(L["ExceptedGuild"], 0.7, 0.7, 0.7, true);
			GameTooltip:AddLine(string.format(L["SeenPlayersNumber"], #(data.children or {})), 0.7, 0.7, 0.7);
		else
			GameTooltip:AddLine(L["MutedGuild"], 0.7, 0.7, 0.7);
		end
		GameTooltip:Show();
		return;
	end

	local entry = data.entry;
	if data.isExcepted then
		GameTooltip:AddLine(L["Exception"], 0, 1, 0);
	elseif data.mutedByGuild then
		GameTooltip:AddLine(string.format(L["MutedViaGuild"], data.mutedByGuild), 1, 0.5, 0);
		GameTooltip:AddLine(L["UnmutedTheGuild"], 0.7, 0.7, 0.7);
	elseif data.exceptedByGuild then
		GameTooltip:AddLine(string.format(L["ExceptedViaGuild"], data.exceptedByGuild), 0, 1, 0);
	end

	if entry then
		local status = Mute.WatcherStatus and Mute.WatcherStatus(entry) or "unknown";
		GameTooltip:AddLine(string.format(L["WatcherEntry"],status), 0.7, 0.7, 0.7);
		if entry.guild and not data.mutedByGuild then
			GameTooltip:AddLine(string.format(L["GuildEntry"],entry.guild), 0.7, 0.7, 0.7);
		end
		if entry.count then
			GameTooltip:AddLine(string.format(L["SeenCount"],entry.count), 0.7, 0.7, 0.7);
		end
		if entry.last then
			GameTooltip:AddLine(string.format(L["LastSeen"],date("%Y-%m-%d %H:%M", entry.last)), 0.7, 0.7, 0.7);
		end
	else
		if not data.mutedByGuild then
			GameTooltip:AddLine(L["MutedManually"], 0.7, 0.7, 0.7);
		end
	end
	GameTooltip:Show();
end

local function InitRow(row, data)
	if not row.Text then
		row:RegisterForClicks("LeftButtonUp");
		row.Selected = row:CreateTexture(nil, "BACKGROUND");
		row.Selected:SetAllPoints();
		row.Selected:SetColorTexture(0.25, 0.55, 1, 0.3);

		local highlight = row:CreateTexture(nil, "HIGHLIGHT");
		highlight:SetAllPoints();
		highlight:SetColorTexture(1, 1, 1, 0.1);

		row.collapseBtn = CreateFrame("Button", nil, row);
		row.collapseBtn:SetSize(18, 18);
		row.collapseBtn:SetPoint("LEFT", 4, 0);
		row.collapseBtn:SetScript("OnClick", function()
			if row.data and row.data.isGuild then
				local key = row.data.key;
				expandedNodes[key] = not expandedNodes[key];
				if Mute.OnMuteListChanged then
					Mute.OnMuteListChanged();
				end
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
			end
		end);

		row.ExceptionIcon = row:CreateTexture(nil, "OVERLAY");
		row.ExceptionIcon:SetSize(16, 16);

		row.Realm = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall");
		row.Realm:SetPoint("RIGHT", row, "RIGHT", -6, 0);
		row.Realm:SetJustifyH("RIGHT");

		row.ExceptionIcon:SetPoint("RIGHT", row.Realm, "LEFT", -4, 0);

		row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
		row.Text:SetJustifyH("LEFT");
		row.Text:SetWordWrap(false);

		row:SetScript("OnClick", Row_OnClick);
		row:SetScript("OnEnter", Row_OnEnter);
		row:SetScript("OnLeave", GameTooltip_Hide);
		row.UpdateSelection = UpdateRowSelection;
	end

	row.data = data;
	if data.isGuild then
		row.collapseBtn:Show();
		row.ExceptionIcon:Hide();
		if expandedNodes[data.key] then
			row.collapseBtn:SetNormalAtlas("UI-QuestTrackerButton-Secondary-Collapse");
			row.collapseBtn:SetPushedAtlas("UI-QuestTrackerButton-Secondary-Collapse-Pressed");
		else
			row.collapseBtn:SetNormalAtlas("UI-QuestTrackerButton-Secondary-Expand");
			row.collapseBtn:SetPushedAtlas("UI-QuestTrackerButton-Secondary-Expand-Pressed");
		end
		
		row.Text:ClearAllPoints();
		row.Text:SetPoint("LEFT", row.collapseBtn, "RIGHT", 2, 0);
		row.Text:SetPoint("RIGHT", row.Realm, "LEFT", -4, 0);
		
		row.Text:SetText(data.name);
		row.Realm:SetText((data.isWatcherGuild or data.isExceptionGuild) and string.format("(%d)", #(data.children or {})) or "");
	else
		row.collapseBtn:Hide();
		
		row.Text:ClearAllPoints();
		local indent = (data.mutedByGuild or data.isWatcherChild) and 24 or 8;
		row.Text:SetPoint("LEFT", row, "LEFT", indent, 0);
		if data.isExcepted or data.exceptedByGuild then
			row.ExceptionIcon:Show();
			row.ExceptionIcon:SetAtlas("UI-CastingBar-Shield");
			row.Text:SetPoint("RIGHT", row.ExceptionIcon, "LEFT", -4, 0);
		else
			row.ExceptionIcon:Hide();
			row.Text:SetPoint("RIGHT", row.Realm, "LEFT", -4, 0);
		end
		
		local short, realm = string.match(data.name, "^([^-]+)-(.+)$");
		row.Text:SetText(short or data.name);
		row.Realm:SetText(realm or "");
	end
	UpdateRowSelection(row);
end

local function InitHeader(header, data)
	if not header.Text then
		header.collapseBtn = CreateFrame("Button", nil, header);
		header.collapseBtn:SetSize(18, 18);
		header.collapseBtn:SetPoint("LEFT", 4, 0);
		header.collapseBtn:SetScript("OnClick", function()
			local key = header.data.key;
			if key then
				local currentState = expandedNodes[key];
				if currentState == nil then currentState = true end
				expandedNodes[key] = not currentState;
				
				if Mute.OnMuteListChanged then
					Mute.OnMuteListChanged();
				end
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
			end
		end);
		header.Text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal");
		header.Text:SetPoint("LEFT", header.collapseBtn, "RIGHT", 2, 0);
		header.Text:SetJustifyH("LEFT");
	end
	header.data = data;
	header.Text:SetText(data.text);
	
	local expanded = expandedNodes[data.key];
	if expanded == nil then expanded = true end
	if expanded then
		header.collapseBtn:SetNormalAtlas("UI-QuestTrackerButton-Secondary-Collapse");
		header.collapseBtn:SetPushedAtlas("UI-QuestTrackerButton-Secondary-Collapse-Pressed");
	else
		header.collapseBtn:SetNormalAtlas("UI-QuestTrackerButton-Secondary-Expand");
		header.collapseBtn:SetPushedAtlas("UI-QuestTrackerButton-Secondary-Expand-Pressed");
	end
end

local function GetPopupEditBox(dialog)
	if dialog.GetEditBox then
		return dialog:GetEditBox();
	end
	return dialog.EditBox or dialog.editBox;
end

local function SubmitName(editBox)
	if not editBox then return; end
	local name = strtrim(editBox:GetText() or "");
	if name ~= "" then
		Mute.Muter:AddMute(name);
	end
end

local function SubmitGuild(editBox)
	if not editBox then return; end
	local name = strtrim(editBox:GetText() or "");
	if name ~= "" then
		Mute.Muter:AddGuildMute(name);
	end
end

StaticPopupDialogs["MUTE_ADD_PLAYER"] = {
	text = L["EnterEntryText"],
	button1 = L["MutePlayer"],
	button2 = L["MuteGuild"],
	button3 = CANCEL,
	hasEditBox = true,
	autoCompleteSource = C_AutoComplete.GetAutoCompleteResults,
	autoCompleteArgs = { AUTOCOMPLETE_LIST.IGNORE.include, AUTOCOMPLETE_LIST.IGNORE.exclude },
	maxLetters = 12 + 1 + 64, --name space realm (77 max)
	OnShow = function(self)
		local editBox = GetPopupEditBox(self);
		if editBox then
			editBox:SetText("");
			editBox:SetFocus();
		end
	end,
	OnAccept = function(self) -- Player
		SubmitName(GetPopupEditBox(self));
	end,
	OnCancel = function(self) -- Guild
		SubmitGuild(GetPopupEditBox(self));
		self:Hide();
	end,
	OnAlt = function(self) -- Cancel
		self:Hide()
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide();
	end,
	hasEditBox = true,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
};

local function RefreshView(view)
	if not view.content:IsVisible() then return; end

	local dataProvider, existing, total = BuildData();
	if selectedKey and not existing[selectedKey] then
		selectedKey = nil;
	end

	view.scrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.RetainScrollPosition);
	view.empty:SetShown(total == 0);
	view.unmuteButton:SetEnabled(selectedKey ~= nil);
end

local function RefreshAll()
	for _, view in ipairs(views) do
		RefreshView(view);
	end
end

-- a burst of changes (census report) only rebuilds the list once
local refreshQueued = false;
function Mute.OnMuteListChanged()
	if refreshQueued then return; end
	refreshQueued = true;
	RunNextFrame(function()
		refreshQueued = false;
		RefreshAll();
	end);
end

local SETTINGS_DIALOG_WIDTH = 300;
local SETTINGS_PADDING = 16;
local SETTINGS_CONTENT_WIDTH = SETTINGS_DIALOG_WIDTH - (SETTINGS_PADDING * 2);
local SETTINGS_BUTTON_LEVEL = 515;

local settingsDialog;
local settingsData;

local function IsForeverClient()
	return WOW_PROJECT_ID == WOW_PROJECT_CAMELOT;
end

local function BuildSettingsData()
	settingsData = {};

	-- Header - Muter
	table.insert(settingsData, {
		type = "header",
		label = L["Setting_MuterHeader"],
	});

	-- MuterSettings - AddContextMenu
	table.insert(settingsData, {
		type = "checkbox",
		category = "MuterSettings",
		key = "AddContextMenu",
		label = L["Setting_AddContextMenu"],
		tooltip = L["Setting_AddContextMenuTT"],
	});

	-- MuterSettings - SpeechBubbles
	table.insert(settingsData, {
		type = "checkbox",
		category = "MuterSettings",
		key = "SpeechBubbles",
		label = L["Setting_SpeechBubbles"],
		tooltip = L["Setting_SpeechBubblesTT"],
	});

	-- Header - Watcher
	table.insert(settingsData, {
		type = "header",
		label = L["Watcher"],
	});

	-- WatcherSettings - Chat_Notify
	table.insert(settingsData, {
		type = "checkbox",
		category = "WatcherSettings",
		key = "Chat_Notify",
		label = L["Setting_Chat_Notify"],
		tooltip = L["Setting_Chat_NotifyTT"],
	});

	-- WatcherSettings - PauseWatcher
	table.insert(settingsData, {
		type = "checkbox",
		category = "WatcherSettings",
		key = "PauseWatcher",
		label = L["Setting_PauseWatcher"],
		tooltip = L["Setting_PauseWatcherTT"],
	});

	-- WatcherSettings - UseNetwork
	if IsForeverClient() then
		table.insert(settingsData, {
			type = "checkbox",
			category = "WatcherSettings",
			key = "UseNetwork",
			label = L["Setting_UseNetwork"],
			tooltip = L["Setting_UseNetworkTT"],
		});
	end
end

local function GetDefaultValue(data)
	if data.defaultValue ~= nil then
		return data.defaultValue;
	end
	local defaults = data.category and Mute.DefaultSettings[data.category];
	return defaults and defaults[data.key];
end

local function GetSettingValue(data)
	if data.get then
		return data.get();
	end
	return Mute:GetSetting(data.category, data.key);
end

local function StoreSettingValue(data, value)
	if data.set then
		data.set(value);
	else
		Mute:SetSetting(data.category, data.key, value);
	end
end

local function SetSettingValue(data, value)
	StoreSettingValue(data, value);
	if data.callback then data.callback(value); end
end

local function SummarizeOptions(options, values)
	local selected, total = {}, 0;
	local function Gather(list)
		for _, opt in ipairs(list) do
			if opt.isGroup then
				Gather(opt.children);
			elseif not opt.isDivider and not opt.isTitle then
				total = total + 1;
				local on;
				if values then
					on = values[opt.key];
				else
					on = opt.default ~= false;
				end
				if on then
					selected[#selected + 1] = opt.text;
				end
			end
		end
	end
	Gather(options);

	if #selected == 0 then return NONE; end
	if #selected == total then return ALL; end
	return table.concat(selected, ", ");
end

local function GetDefaultValueString(data)
	local default = GetDefaultValue(data);

	if data.type == "checkbox" then
		if default == nil then return nil; end
		return default and YES or NO;
	elseif data.type == "dropdown" then
		for _, opt in ipairs(data.options) do
			if opt.value == default then
				return opt.text;
			end
		end
	elseif data.type == "slider" then
		if default == nil then return nil; end
		return data.formatter and data.formatter(default) or tostring(default);
	elseif data.type == "multicheckbox" then
		return SummarizeOptions(data.options, nil);
	end
	return nil;
end

local function AttachTooltip(frame, data)
	frame:HookScript("OnEnter", function(self)
		if not data.tooltip then return; end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(data.label, 1, 1, 1);
		GameTooltip:AddLine(data.tooltip, nil, nil, nil, true);

		local defaultString = GetDefaultValueString(data);
		if defaultString then
			GameTooltip:AddLine(" ");
			GameTooltip:AddLine(DEFAULT .. ": |cFFFFFFFF" .. defaultString .. "|r", 1, 0.82, 0);
		end
		GameTooltip:Show();
	end);
	frame:HookScript("OnLeave", GameTooltip_Hide);
end

local function CreateRowLabel(row, data)
	local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
	label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2);
	label:SetJustifyH("LEFT");
	label:SetText(data.label);
	return label;
end

local function BuildHeader(row, data)
	local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal");
	label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -8);
	label:SetText(data.label);
	return 28;
end

local function BuildCheckbox(row, data)
	local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate");
	check:SetSize(26, 26);
	check:SetPoint("TOPLEFT", row, "TOPLEFT", -4, 0);

	local textWidth = SETTINGS_CONTENT_WIDTH - 26;
	local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
	label:SetPoint("LEFT", check, "RIGHT", 2, 0);
	label:SetWidth(textWidth);
	label:SetJustifyH("LEFT");
	label:SetText(data.label);
	check:SetHitRectInsets(0, -(textWidth + 2), 0, 0);

	check:SetScript("OnClick", function(self)
		local checked = self:GetChecked() and true or false;
		SetSettingValue(data, checked);
		PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF);
	end);
	AttachTooltip(check, data);

	function row:Refresh()
		check:SetChecked(GetSettingValue(data) and true or false);
	end

	return math.max(26, label:GetStringHeight() + 8);
end

local function BuildDropdown(row, data)
	local label = CreateRowLabel(row, data);

	local dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate");
	dropdown:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4);
	dropdown:SetWidth(SETTINGS_CONTENT_WIDTH);

	local function UpdateText()
		local current = GetSettingValue(data);
		for _, opt in ipairs(data.options) do
			if opt.value == current then
				dropdown.Text:SetText(opt.text);
				return;
			end
		end
	end

	dropdown:SetupMenu(function(_, rootDescription)
		rootDescription:SetScrollMode(300);
		for _, option in ipairs(data.options) do
			rootDescription:CreateRadio(option.text, function()
				return GetSettingValue(data) == option.value;
			end, function()
				SetSettingValue(data, option.value);
				UpdateText();
			end, option.value);
		end
	end);
	AttachTooltip(dropdown, data);

	row.Refresh = UpdateText;
	return 54;
end

local function BuildSlider(row, data)
	local label = CreateRowLabel(row, data);

	local formatter = data.formatter or function(value) return string.format("%g", value); end
	local options = Settings.CreateSliderOptions(data.min, data.max, data.step);
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter);

	local slider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate");
	slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4);
	slider:SetWidth(SETTINGS_CONTENT_WIDTH);
	slider.RightText:ClearAllPoints();
	slider.RightText:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2);

	local function GetCurrent()
		return tonumber(GetSettingValue(data)) or GetDefaultValue(data) or data.min;
	end

	local syncing = true;
	slider:Init(GetCurrent(), options.minValue, options.maxValue, options.steps, options.formatters);
	slider:RegisterCallback("OnValueChanged", function(_, value)
		if syncing then return; end
		SetSettingValue(data, value);
	end, slider);
	syncing = false;

	AttachTooltip(slider.Slider, data);

	function row:Refresh()
		syncing = true;
		slider:SetValue(GetCurrent());
		syncing = false;
	end

	return 54;
end

local function BuildMultiCheckbox(row, data)
	local label = CreateRowLabel(row, data);

	local dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate");
	dropdown:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4);
	dropdown:SetWidth(SETTINGS_CONTENT_WIDTH);
	if dropdown.Text then
		dropdown.Text:SetWordWrap(false);
	end

	-- fills in any option that has no saved value yet
	local function GetValues()
		local values = GetSettingValue(data);
		if type(values) ~= "table" then
			values = {};
		end

		local needsSave = false;
		local function InitDefaults(list)
			for _, opt in ipairs(list) do
				if opt.isGroup then
					InitDefaults(opt.children);
				elseif not opt.isDivider and not opt.isTitle and values[opt.key] == nil then
					values[opt.key] = opt.default ~= false;
					needsSave = true;
				end
			end
		end
		InitDefaults(data.options);

		if needsSave then
			StoreSettingValue(data, values);
		end
		return values;
	end

	local function UpdateText()
		dropdown.Text:SetText(SummarizeOptions(data.options, GetValues()));
	end

	dropdown:SetupMenu(function(_, rootDescription)
		rootDescription:SetScrollMode(300);
		local values = GetValues();

		local function BuildMenu(desc, list)
			for _, option in ipairs(list) do
				if option.isGroup then
					BuildMenu(desc:CreateButton(option.text), option.children);
				elseif option.isDivider then
					desc:CreateDivider();
				elseif option.isTitle then
					desc:CreateTitle(option.text);
				else
					local checkbox = desc:CreateCheckbox(option.text, function()
						return values[option.key];
					end, function()
						values[option.key] = not values[option.key];
						SetSettingValue(data, values);
						UpdateText();
					end);

					if option.tooltip then
						checkbox:SetTooltip(function(tooltip)
							GameTooltip_SetTitle(tooltip, option.text);
							GameTooltip_AddNormalLine(tooltip, option.tooltip);
						end);
					end
				end
			end
		end
		BuildMenu(rootDescription, data.options);
	end);
	AttachTooltip(dropdown, data);

	row.Refresh = UpdateText;
	return 54;
end

local settingBuilders = {
	header = BuildHeader,
	checkbox = BuildCheckbox,
	dropdown = BuildDropdown,
	slider = BuildSlider,
	multicheckbox = BuildMultiCheckbox,
};

local function GetSettingsDialog()
	if settingsDialog then return settingsDialog; end

	BuildSettingsData();

	local dialog = CreateFrame("Frame", "MuteSettingsDialog", UIParent);
	dialog:SetSize(SETTINGS_DIALOG_WIDTH, 390);
	dialog:SetFrameStrata("DIALOG");
	dialog:SetToplevel(true);
	dialog:EnableMouse(true);
	dialog:Hide();

	dialog.Border = CreateFrame("Frame", nil, dialog, "DialogBorderOpaqueTemplate");
	dialog.Border:SetAllPoints();

	dialog.Header = CreateFrame("Frame", nil, dialog, "DialogHeaderTemplate");
	local title = string.format("%s %s", TITLE, SETTINGS);
	if dialog.Header.Setup then
		dialog.Header:Setup(title);
	else
		dialog.Header.Text:SetText(title);
	end

	dialog.rows = {};
	local y = -34;
	for _, data in ipairs(settingsData) do
		local builder = settingBuilders[data.type];
		if builder then
			local row = CreateFrame("Frame", nil, dialog);
			row:SetPoint("TOPLEFT", dialog, "TOPLEFT", SETTINGS_PADDING, y);
			row:SetSize(SETTINGS_CONTENT_WIDTH, 30);

			local height = builder(row, data);
			row:SetHeight(height);
			if row.Refresh then
				dialog.rows[#dialog.rows + 1] = row;
			end
			y = y - height;
		end
	end

	local doneButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate");
	doneButton:SetSize(100, 22);
	doneButton:SetText(DONE);
	doneButton:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 16);
	doneButton:SetScript("OnClick", function()
		dialog:Hide();
	end);

	--dialog:SetHeight(-y + 22 + 16 + 12);

	dialog:SetScript("OnShow", function(self)
		for _, row in ipairs(self.rows) do
			row:Refresh();
		end
	end);

	settingsDialog = dialog;
	return dialog;
end

local function ToggleSettingsDialog(host)
	local dialog = GetSettingsDialog();
	if dialog:IsShown() and dialog:GetParent() == host then
		dialog:Hide();
		return;
	end

	dialog:SetParent(host);
	dialog:SetFrameLevel(750);
	dialog:ClearAllPoints();
	dialog:SetPoint("CENTER", host, "CENTER", 0, 0);
	dialog:Show();
	dialog:Raise();
end

local function CreateSettingsButton(content)
	local button = CreateFrame("Button", nil, content);
	button:SetSize(16, 16);
	button:SetPoint("TOPRIGHT", content, "TOPRIGHT", -30, -3);
	button:SetNormalAtlas("QuestLog-icon-setting");
	button:SetHighlightAtlas("QuestLog-icon-setting", "ADD");
	button:SetFrameLevel(SETTINGS_BUTTON_LEVEL);

	local function SetIconOffset(x, y)
		for _, tex in pairs({ button:GetNormalTexture(), button:GetHighlightTexture() }) do
			tex:ClearAllPoints();
			tex:SetSize(16, 16);
			tex:SetPoint("CENTER", button, "CENTER", x, y);
		end
	end

	button:SetScript("OnMouseDown", function() SetIconOffset(1, -1); end);
	button:SetScript("OnMouseUp", function() SetIconOffset(0, 0); end);
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(SETTINGS, 1, 1, 1);
		GameTooltip:Show();
	end);
	button:SetScript("OnLeave", function()
		SetIconOffset(0, 0);
		GameTooltip:Hide();
	end);
	button:SetScript("OnClick", function()
		ToggleSettingsDialog(content);
	end);

	return button;
end

local function CreateMuteList(host, inset)
	local content = CreateFrame("Frame", nil, host);
	content:SetAllPoints(host);

	local scrollBox = CreateFrame("Frame", nil, content, "WowScrollBoxList");
	scrollBox:SetPoint("TOPLEFT", inset, "TOPLEFT", 5, -5);
	scrollBox:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -22, 2);

	local scrollBar = CreateFrame("EventFrame", nil, content, "MinimalScrollBar");
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 5, -3);
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 5, 3);

	local scrollView = CreateScrollBoxListLinearView();
	scrollView:SetElementExtent(ROW_HEIGHT);
	scrollView:SetElementFactory(function(factory, elementData)
		if elementData.header then
			factory("Frame", InitHeader);
		else
			factory("Button", InitRow);
		end
	end);
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, scrollView);

	local empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisable");
	empty:SetPoint("CENTER", inset, "CENTER", 0, 0);
	empty:SetText(L["NoMutedPlayers"]);
	empty:Hide();

	local muteButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate");
	muteButton:SetSize(122, 22);
	muteButton:SetText(ADD);
	muteButton:SetPoint("BOTTOMRIGHT", host, "BOTTOM", -2, 8);
	muteButton:SetScript("OnClick", function()
		StaticPopup_Show("MUTE_ADD_PLAYER");
	end);

	local unmuteButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate");
	unmuteButton:SetSize(122, 22);
	unmuteButton:SetText(REMOVE);
	unmuteButton:SetPoint("BOTTOMLEFT", host, "BOTTOM", 2, 8);
	unmuteButton:Disable();
	unmuteButton:SetScript("OnClick", function()
		if not IsShiftKeyDown() then return; end
		if not selectedKey then return; end

		if selectedKey:match("^GUILDEXC:") then
			local g = nodeGuildNames[selectedKey];
			if g then Mute.Muter:RemoveGuildException(g); end
		elseif selectedKey:match("^WATCHER_GUILD:") then
			local g = nodeGuildNames[selectedKey];
			if g then Mute.Muter:AddGuildException(g); end
		elseif selectedKey:match("^GUILD:") then
			Mute.Muter:RemoveGuildMute(selectedKey:sub(7));
		else
			local seen = WatcherData_DB and WatcherData_DB.seen;
			local entry = seen and seen[selectedKey];
			if Mute.Muter:IsException(selectedKey) then
			elseif entry and entry.guild and not entry.addon and Mute.Muter:IsGuildExcepted(entry.guild) then
				Mute.Muter:AddMute(entry.name or selectedKey);
			else
				Mute.Muter:RemoveMute(selectedKey);
			end
		end
	end);
	unmuteButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(L["HoldShiftToConfirm"], 1, 0.8, 0);
		GameTooltip:Show();
	end);
	unmuteButton:SetScript("OnLeave", function()
		GameTooltip:Hide();
	end);

	local view = {
		content = content,
		scrollBox = scrollBox,
		empty = empty,
		muteButton = muteButton,
		unmuteButton = unmuteButton,
	};
	view.settingsButton = CreateSettingsButton(content);
	views[#views + 1] = view;

	content:SetScript("OnShow", function()
		RefreshView(view);
	end);

	return view;
end

local standalone;
local function GetStandaloneFrame()
	if standalone then return standalone; end

	local frame = CreateFrame("Frame", "MuteListFrame", UIParent, "ButtonFrameTemplate");
	frame:SetSize(300, 424);
	frame:SetPoint("CENTER");
	frame:SetToplevel(true);
	frame:SetClampedToScreen(true);
	frame:SetMovable(true);
	frame:EnableMouse(true);
	frame:RegisterForDrag("LeftButton");
	frame:SetScript("OnDragStart", frame.StartMoving);
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing);

	ButtonFrameTemplate_HidePortrait(frame);
	frame:SetTitle(TITLE);
	if frame.TopTileStreaks then frame.TopTileStreaks:Hide(); end
	frame.Inset:ClearAllPoints();
	frame.Inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 11, -28);
	frame.Inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 36);

	local view = CreateMuteList(frame, frame.Inset);
	view.content:Hide();

	frame.minTabWidth = 70;
	local tabs = {};
	local contents = {};
	local titles = { [1] = TITLE };

	local function MakeTab(id, text, anchorTo)
		local tab = CreateFrame("Button", "MuteStandaloneTab" .. id, frame, "PanelTabButtonTemplate");
		tab:SetID(id);
		tab:SetText(text);
		if anchorTo then
			tab:SetPoint("TOPLEFT", anchorTo, "TOPRIGHT", 3, 0);
		else
			tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 2);
		end
		PanelTemplates_TabResize(tab, 0, nil, frame.minTabWidth);
		tabs[id] = tab;
		return tab;
	end

	local muteTab = MakeTab(1, L["MUTE"] or "Mute");
	contents[1] = view.content;

	local lastTab = muteTab;
	for _, def in ipairs(Mute.IgnoreTabs or {}) do
		local id = #tabs + 1;
		lastTab = MakeTab(id, def.text, lastTab);
		titles[id] = def.title or def.text;
		local extra = def.create(frame, frame.Inset);
		extra:Hide();
		contents[id] = extra;
	end

	PanelTemplates_SetNumTabs(frame, #tabs);

	frame.ShowTab = function(self, id)
		for tabId, tab in ipairs(tabs) do
			if tabId == id then
				PanelTemplates_SelectTab(tab);
			else
				PanelTemplates_DeselectTab(tab);
			end
		end

		for tabId, content in pairs(contents) do
			if content then
				content:SetShown(tabId == id);
			end
		end
		self:SetTitle(titles[id] or TITLE);
	end

	local function OnTabClick(self)
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB);
		frame:ShowTab(self:GetID());
	end

	for _, tab in ipairs(tabs) do
		tab:SetScript("OnClick", OnTabClick);
	end

	frame:ShowTab(1);

	tinsert(UISpecialFrames, "MuteListFrame");
	frame:Hide();

	standalone = frame;
	return frame;
end

function Mute:ToggleMuteList(tabID)
	local frame = GetStandaloneFrame();
	if tabID then
		frame:ShowTab(tabID);
		frame:Show();
	else
		frame:SetShown(not frame:IsShown());
	end
end

function Mute:ToggleMuteList()
	local frame = GetStandaloneFrame();
	frame:SetShown(not frame:IsShown());
end

SLASH_MUTELIST1 = L["SLASH_CHAT_MUTELIST1"]; -- localized
SLASH_MUTELIST2 = L["SLASH_CHAT_MUTELIST2"]; -- english
SlashCmdList["MUTELIST"] = function()
	Mute:ToggleMuteList();
end;

local hooked = false;

local function HookIgnoreWindow()
	if hooked then return; end
	local window = FriendsFrame and FriendsFrame.IgnoreListWindow;
	if not window then return; end
	hooked = true;

	window:ClearAllPoints();
	window:SetPoint("TOPLEFT", FriendsFrame, "TOPRIGHT", -2, 0);
	window:EnableMouse(true);
	window:SetSize(300, 424);
	if window.Inset then
		window.Inset:ClearAllPoints();
		window.Inset:SetPoint("TOPLEFT", window, "TOPLEFT", 11, -28);
		window.Inset:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -6, 36);
	end

	local view = CreateMuteList(window, window.Inset);
	view.content:Hide();

	if window.UnignorePlayerButton then
		window.UnignorePlayerButton:ClearAllPoints();
		window.UnignorePlayerButton:SetSize(122, 22);
		window.UnignorePlayerButton:SetPoint("BOTTOMLEFT", window, "BOTTOM", 2, 8);

		-- require shift key
		local origOnClick = window.UnignorePlayerButton:GetScript("OnClick");
		window.UnignorePlayerButton:SetScript("OnClick", function(self, button, down)
			if not IsShiftKeyDown() then return; end
			if origOnClick then
				origOnClick(self, button, down);
			end
		end);

		window.UnignorePlayerButton:HookScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["HoldShiftToConfirm"], 1, 0.8, 0);
			GameTooltip:Show();
		end);
		window.UnignorePlayerButton:HookScript("OnLeave", GameTooltip_Hide);
	end

	local addIgnoreButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate");
	addIgnoreButton:SetSize(122, 22);
	addIgnoreButton:SetText(IGNORE_PLAYER);
	addIgnoreButton:SetPoint("BOTTOMRIGHT", window, "BOTTOM", -2, 8);
	addIgnoreButton:SetScript("OnClick", function()
		StaticPopup_Show("ADD_IGNORE");
	end);

	window.minTabWidth = window.minTabWidth or 70;

	local tabs = {};
	local extraContents = {};
	local titles = { [1] = IGNORE_LIST, [2] = TITLE };

	local function MakeTab(id, text, anchorTo)
		local tab = CreateFrame("Button", "MuteIgnoreWindowTab" .. id, window, "PanelTabButtonTemplate");
		tab:SetID(id);
		tab:SetText(text);
		if anchorTo then
			tab:SetPoint("TOPLEFT", anchorTo, "TOPRIGHT", 3, 0);
		else
			tab:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 5, 2);
		end
		PanelTemplates_TabResize(tab, 0, nil, window.minTabWidth);
		tabs[id] = tab;
		return tab;
	end

	local ignoreTab = MakeTab(1, IGNORE);
	local muteTab = MakeTab(2, L["MUTE"], ignoreTab);

	local lastTab = muteTab;
	for _, def in ipairs(Mute.IgnoreTabs or {}) do
		local id = #tabs + 1;
		lastTab = MakeTab(id, def.text, lastTab);
		titles[id] = def.title or def.text;
		local extra = def.create(window, window.Inset);
		extra:Hide();
		extraContents[id] = extra;
	end

	local function ShowTab(id)
		local ignoreMode = (id == 1);

		for tabId, tab in ipairs(tabs) do
			if tabId == id then
				PanelTemplates_SelectTab(tab);
			else
				PanelTemplates_DeselectTab(tab);
			end
		end

		window.ScrollBox:SetShown(ignoreMode);
		window.ScrollBar:SetShown(ignoreMode);
		window.UnignorePlayerButton:SetShown(ignoreMode);
		addIgnoreButton:SetShown(ignoreMode);

		view.content:SetShown(id == 2);
		for tabId, extra in pairs(extraContents) do
			extra:SetShown(tabId == id);
		end
		window:SetTitle(titles[id] or TITLE);

		if ignoreMode and window:IsShown() and IgnoreList_Update then
			IgnoreList_Update();
		end
	end

	local function OnTabClick(self)
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB);
		ShowTab(self:GetID());
	end
	for _, tab in ipairs(tabs) do
		tab:SetScript("OnClick", OnTabClick);
	end

	window:HookScript("OnHide", function()
		ShowTab(1);
	end);

	ShowTab(1);
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_FriendsFrame", HookIgnoreWindow);

local eventFrame = CreateFrame("Frame");
eventFrame:RegisterEvent("PLAYER_LOGIN");
eventFrame:SetScript("OnEvent", function()
	HookIgnoreWindow();
end);

local function CheckIfThingIsOpenAndInsertName(name)
	local popup = StaticPopup_Visible("MUTE_ADD_PLAYER");
	if popup then
		_G[popup .. "EditBox"]:SetText(name);
		return true;
	end
	return false;
end

local function MyNotGhostLinkHandler(_, haha, ...)
	local GUID, LinkThing, Button = ...
	local linkType, name = LinkUtil.SplitLinkOptions(GUID);
	if linkType == LinkTypes.Player then
		CheckIfThingIsOpenAndInsertName(name);
	end
end

EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkClick", MyNotGhostLinkHandler);