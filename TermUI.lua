local addonName, Mute = ...;
local L = Mute.L;

local ROW_HEIGHT = 20;
local views = {};
local selectedTerm;

local MODES = {
	{
		value = "contains",
		text = L["Term_Contains"],
		tooltip = L["Term_ContainsTT"],
	},
	{
		value = "word",
		text = L["Term_Word"],
		tooltip = L["Term_WordTT"],
	},
	{
		value = "contains_all",
		text = L["Term_ContainsAll"],
		tooltip = L["Term_ContainsAllTT"],
	},
	{
		value = "advanced",
		text = L["Term_Advanced"],
		tooltip = L["Term_AdvancedTT"],
	},
};

local function ModeText(mode)
	for _, m in ipairs(MODES) do
		if m.value == mode then return m.text; end
	end
	return MODES[1].text;
end

local function BuildData()
	local dataProvider = CreateDataProvider();
	local terms = Mute.Muter:GetTerms();
	local found = false;
	for _, term in ipairs(terms) do
		dataProvider:Insert({ term = term });
		if term == selectedTerm then found = true; end
	end
	if not found then selectedTerm = nil; end
	return dataProvider, #terms;
end

local function UpdateRowSelection(row)
	if row and row.Selected then
		row.Selected:SetShown(row.data ~= nil and row.data.term == selectedTerm);
	end
end

local function Row_OnClick(self)
	if not self.data then return; end
	selectedTerm = self.data.term;
	Mute.UpdateTermSelection();
end

local function Row_OnEnter(self)
	local data = self.data;
	if not data then return; end
	local term = data.term;

	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(term.pattern, 1, 1, 1);
	for _, m in ipairs(MODES) do
		if m.value == term.mode then
			GameTooltip:AddLine(m.tooltip, 0.7, 0.7, 0.7, true);
		end
	end
	GameTooltip:AddLine(string.format(L["Term_Blocked"], term.hits or 0), 0.7, 0.7, 0.7);
	if term.enabled == false then
		GameTooltip:AddLine(L["Disabled"], 1, 0.5, 0);
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

		row.Check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate");
		row.Check:SetSize(22, 22);
		row.Check:SetPoint("LEFT", row, "LEFT", 2, 0);
		row.Check:SetScript("OnClick", function(self)
			local checked = self:GetChecked() and true or false;
			if row.data then
				Mute.Muter:SetTermEnabled(row.data.term, checked);
			end
			PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF);
		end);
		row.Check:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(L["Enabled"], 1, 1, 1);
			GameTooltip:Show();
		end);
		row.Check:SetScript("OnLeave", GameTooltip_Hide);

		row.Mode = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall");
		row.Mode:SetPoint("RIGHT", row, "RIGHT", -6, 0);
		row.Mode:SetJustifyH("RIGHT");

		row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
		row.Text:SetPoint("LEFT", row.Check, "RIGHT", 2, 0);
		row.Text:SetPoint("RIGHT", row.Mode, "LEFT", -4, 0);
		row.Text:SetJustifyH("LEFT");
		row.Text:SetWordWrap(false);

		row:SetScript("OnClick", Row_OnClick);
		row:SetScript("OnEnter", Row_OnEnter);
		row:SetScript("OnLeave", GameTooltip_Hide);
	end

	row.data = data;
	local term = data.term;
	local enabled = term.enabled ~= false;
	row.Check:SetChecked(enabled);
	row.Text:SetText(term.pattern);
	row.Text:SetFontObject(enabled and GameFontHighlight or GameFontDisable);
	row.Mode:SetText(ModeText(term.mode));
	UpdateRowSelection(row);
end

local function RefreshView(view)
	if not view.content:IsVisible() then return; end
	local dataProvider, total = BuildData();
	view.scrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.RetainScrollPosition);
	view.empty:SetShown(total == 0);
	Mute.UpdateTermSelection();
end

function Mute.UpdateTermSelection()
	for _, view in ipairs(views) do
		view.scrollBox:ForEachFrame(UpdateRowSelection);
		view.editButton:SetEnabled(selectedTerm ~= nil);
		view.removeButton:SetEnabled(selectedTerm ~= nil);
	end
end

local refreshQueued = false;
function Mute.OnTermsChanged()
	if refreshQueued then return; end
	refreshQueued = true;
	RunNextFrame(function()
		refreshQueued = false;
		for _, view in ipairs(views) do
			RefreshView(view);
		end
	end);
end

local DIALOG_WIDTH = 320;
local DIALOG_PADDING = 16;

local termDialog;

local function UpdateValidation(dialog)
	if not dialog.acceptButton or not dialog.errorText then return false; end
	local pattern = strtrim(dialog.editBox:GetText() or "");
	local ok, reason = false, nil;
	if pattern ~= "" then
		ok, reason = Mute.Muter:ValidateTerm(pattern, dialog.mode);
	end

	if pattern == "" or ok then
		dialog.errorText:SetText("");
	else
		local msg = reason and L[reason];
		if type(msg) ~= "string" or msg == reason then msg = L["Term_Invalid"]; end
		dialog.errorText:SetText(msg);
	end
	dialog.acceptButton:SetEnabled(ok and true or false);
	return ok and true or false;
end

local function AcceptDialog(dialog)
	if not UpdateValidation(dialog) then return; end
	local pattern = strtrim(dialog.editBox:GetText() or "");
	if dialog.editing then
		Mute.Muter:EditTerm(dialog.editing, pattern, dialog.mode);
	else
		Mute.Muter:AddTerm(pattern, dialog.mode);
	end
	dialog:Hide();
end

local function GetTermDialog()
	if termDialog then return termDialog; end

	local dialog = CreateFrame("Frame", "MuteTermDialog", UIParent);
	dialog:SetSize(DIALOG_WIDTH, 215);
	dialog:SetFrameStrata("DIALOG");
	dialog:SetToplevel(true);
	dialog:EnableMouse(true);
	dialog:Hide();
	dialog.mode = "contains";

	dialog.Border = CreateFrame("Frame", nil, dialog, "DialogBorderOpaqueTemplate");
	dialog.Border:SetAllPoints();

	dialog.Header = CreateFrame("Frame", nil, dialog, "DialogHeaderTemplate");

	local info = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	info:SetPoint("TOPLEFT", dialog, "TOPLEFT", DIALOG_PADDING, -36);
	info:SetWidth(DIALOG_WIDTH - DIALOG_PADDING * 2);
	info:SetJustifyH("LEFT");
	info:SetWordWrap(true);
	info:SetText(L["Term_Help"]);

	local editBox = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate");
	editBox:SetSize(DIALOG_WIDTH - DIALOG_PADDING * 2 - 12, 22);
	editBox:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 6, -8);
	editBox:SetAutoFocus(false);
	editBox:SetMaxLetters(200);
	editBox:SetScript("OnEnterPressed", function() AcceptDialog(dialog); end);
	editBox:SetScript("OnEscapePressed", function() dialog:Hide(); end);
	editBox:SetScript("OnTextChanged", function() UpdateValidation(dialog); end);
	dialog.editBox = editBox;

	local modeLabel = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormal");
	modeLabel:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", -6, -12);
	modeLabel:SetText(L["Term_MatchType"]);

	local dropdown = CreateFrame("DropdownButton", nil, dialog, "WowStyle1DropdownTemplate");
	dropdown:SetPoint("TOPLEFT", modeLabel, "BOTTOMLEFT", 0, -4);
	dropdown:SetWidth(DIALOG_WIDTH - DIALOG_PADDING * 2);
	dropdown:SetupMenu(function(_, rootDescription)
		for _, option in ipairs(MODES) do
			local radio = rootDescription:CreateRadio(option.text, function()
				return dialog.mode == option.value;
			end, function()
				dialog.mode = option.value;
				UpdateValidation(dialog);
			end, option.value);
			radio:SetTooltip(function(tooltip)
				GameTooltip_SetTitle(tooltip, option.text);
				GameTooltip_AddNormalLine(tooltip, option.tooltip);
			end);
		end
	end);
	dialog.dropdown = dropdown;

	local errorText = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	errorText:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -6);
	errorText:SetWidth(DIALOG_WIDTH - DIALOG_PADDING * 2);
	errorText:SetHeight(28);
	errorText:SetJustifyH("LEFT");
	errorText:SetJustifyV("TOP");
	errorText:SetWordWrap(true);
	errorText:SetTextColor(1, 0.25, 0.25);
	dialog.errorText = errorText;

	local acceptButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate");
	acceptButton:SetSize(100, 22);
	acceptButton:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -2, 16);
	acceptButton:SetText(ACCEPT);
	acceptButton:SetScript("OnClick", function() AcceptDialog(dialog); end);
	dialog.acceptButton = acceptButton;

	local cancelButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate");
	cancelButton:SetSize(100, 22);
	cancelButton:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 2, 16);
	cancelButton:SetText(CANCEL);
	cancelButton:SetScript("OnClick", function() dialog:Hide(); end);

	termDialog = dialog;
	return dialog;
end

local function OpenTermDialog(host, term)
	local dialog = GetTermDialog();

	dialog:SetParent(host);
	dialog:SetFrameStrata("DIALOG");
	dialog:ClearAllPoints();
	dialog:SetPoint("CENTER", host, "CENTER", 0, 0);

	dialog.editing = term;
	dialog.mode = term and term.mode or "contains";

	local title = term and L["Term_EditTitle"] or L["Term_AddTitle"];
	if dialog.Header.Setup then
		dialog.Header:Setup(title);
	else
		dialog.Header.Text:SetText(title);
	end

	dialog.editBox:SetText(term and term.pattern or "");
	dialog.dropdown:GenerateMenu();
	UpdateValidation(dialog);
	dialog:Show();
	dialog:Raise();
	dialog.editBox:SetFocus();
end

local function CreateTermList(host, inset)
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
	scrollView:SetElementFactory(function(factory)
		factory("Button", InitRow);
	end);
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, scrollView);

	local empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisable");
	empty:SetPoint("CENTER", inset, "CENTER", 0, 0);
	empty:SetWidth(200);
	empty:SetText(L["Term_Empty"]);
	empty:Hide();

	local editButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate");
	editButton:SetSize(90, 22);
	editButton:SetText(EDIT);
	editButton:SetPoint("BOTTOM", host, "BOTTOM", 0, 8);
	editButton:Disable();
	editButton:SetScript("OnClick", function()
		if selectedTerm then OpenTermDialog(content, selectedTerm); end
	end);

	local addButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate");
	addButton:SetSize(90, 22);
	addButton:SetText(ADD);
	addButton:SetPoint("RIGHT", editButton, "LEFT", -4, 0);
	addButton:SetScript("OnClick", function()
		OpenTermDialog(content, nil);
	end);

	local removeButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate");
	removeButton:SetSize(90, 22);
	removeButton:SetText(REMOVE);
	removeButton:SetPoint("LEFT", editButton, "RIGHT", 4, 0);
	removeButton:Disable();
	removeButton:SetScript("OnClick", function()
		if not IsShiftKeyDown() then return; end
		if selectedTerm then
			Mute.Muter:RemoveTerm(selectedTerm);
		end
	end);
	removeButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(L["HoldShiftToConfirm"], 1, 0.8, 0);
		GameTooltip:Show();
	end);
	removeButton:SetScript("OnLeave", GameTooltip_Hide);

	local view = {
		content = content,
		scrollBox = scrollBox,
		empty = empty,
		addButton = addButton,
		editButton = editButton,
		removeButton = removeButton,
	};
	views[#views + 1] = view;

	content:SetScript("OnShow", function()
		RefreshView(view);
	end);

	return content;
end

local standalone;
local function GetStandaloneFrame()
	if standalone then return standalone; end

	local frame = CreateFrame("Frame", "MuteTermsFrame", UIParent, "ButtonFrameTemplate");
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
	frame:SetTitle(L["TermsList"]);
	if frame.TopTileStreaks then frame.TopTileStreaks:Hide(); end
	frame.Inset:ClearAllPoints();
	frame.Inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 11, -28);
	frame.Inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 36);

	CreateTermList(frame, frame.Inset);

	tinsert(UISpecialFrames, "MuteTermsFrame");
	frame:Hide();

	standalone = frame;
	return frame;
end

function Mute:ToggleTermList()
	if Mute.ToggleMuteList then
		Mute:ToggleMuteList(2);
	end
end

SLASH_MUTETERMS1 = "/muteterms";
SlashCmdList["MUTETERMS"] = function()
	Mute:ToggleTermList();
end;

Mute.IgnoreTabs = Mute.IgnoreTabs or {};
table.insert(Mute.IgnoreTabs, {
	text = L["Terms"],
	title = L["TermsList"],
	create = function(window, inset)
		return CreateTermList(window, inset);
	end,
});