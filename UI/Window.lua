-- Oghoule's Warpath : moteur (Window.lua) - voir Core.lua
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end

------------------------------------------------------------------
-- Fenetre (sous la minimap par defaut)
------------------------------------------------------------------
function CreateUI()
    f = CreateFrame("Frame", "WarpathFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(W, 200)
    if DB.wpos then
        f:SetPoint(DB.wpos[1], UIParent, DB.wpos[2], DB.wpos[3], DB.wpos[4])
    elseif Minimap then
        f:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 12, -36)
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -240)
    end
    local bg = Tex(f, COL.bg, 0.90, "BACKGROUND"); bg:SetAllPoints()
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not DB.locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        DB.wpos = { p, rp, x, y }
    end)

    -- (ordre de creation garde : title, text, list, coord)
    f.title = FS(f, 9, COL.gold, FONT, "CENTER"); f.title:SetWidth(INNER)
    f.text = FS(f, 12, COL.soft, FONT, "LEFT"); f.text:SetWidth(INNER)
    if f.text.SetJustifyV then f.text:SetJustifyV("TOP") end
    if f.text.SetWordWrap then f.text:SetWordWrap(true) end
    if f.text.SetSpacing then f.text:SetSpacing(2) end
    f.nextRule = TitledRule(f, INNER)
    f.list = f.nextRule.label
    f.coord = FS(f, 9, COL.gold, FONT, "CENTER"); f.coord:SetWidth(INNER)
    f.xph = FS(f, 9, COL.faint, FONT, "CENTER"); f.xph:SetWidth(INNER); f.xph:Hide() -- XP/h actif (Journal.lua)

    f.name = FS(f, 13, COL.white, FONT, "CENTER"); f.name:SetWidth(INNER)
    f.div = Divider(f, INNER)

    f.kindRow = CreateFrame("Frame", nil, f); f.kindRow:SetSize(INNER, 12)
    f.kind = FS(f.kindRow, 9, COL.green, FONT, "LEFT"); f.kind:SetPoint("LEFT")
    f.dist = FS(f.kindRow, 9, COL.gold, FONT, "RIGHT"); f.dist:SetPoint("RIGHT")
    -- clic sur l'en-tete (le crochet) d'une etape passee ou validee a la main : on l'annule
    if f.kindRow.EnableMouse then f.kindRow:EnableMouse(true) end
    f.kindRow:SetScript("OnMouseUp", function()
        local i = peek or focus or current
        if steps and i and Restorable(i) then Restore(i) end
    end)

    f.qtitle = FS(f, 20, COL.white, DISPLAY, "LEFT"); f.qtitle:SetWidth(INNER)
    if f.qtitle.SetWordWrap then f.qtitle:SetWordWrap(true) end

    f.route = {}
    for k = 1, 3 do
        local row = CreateFrame("Frame", nil, f); row:SetSize(INNER, 16)
        row.gem = Diamond(row, 7, COL.white); row.gem:SetPoint("LEFT", -2, 0)
        row.mode = FS(row, 9, COL.accent, FONT, "RIGHT"); row.mode:SetPoint("RIGHT")
        row.name = FS(row, 12, COL.white, FONT, "LEFT"); row.name:SetPoint("LEFT", 16, 0); row.name:SetPoint("RIGHT", row.mode, "LEFT", -6, 0)
        if row.name.SetWordWrap then row.name:SetWordWrap(false) end
        row:Hide()
        f.route[k] = row
    end

    f.chainBtn = CreateFrame("Button", nil, f); f.chainBtn:SetSize(INNER, 16)
    f.chainBtn.label = FS(f.chainBtn, 11, COL.accent, FONT, "LEFT"); f.chainBtn.label:SetPoint("LEFT")
    local hl = Tex(f.chainBtn, COL.accent, 0.08, "HIGHLIGHT"); hl:SetAllPoints()
    f.chainBtn.gems = {}
    for k = 10, 1, -1 do
        local g = Diamond(f.chainBtn, 5, COL.line, true)
        g:SetPoint("RIGHT", f.chainBtn, "RIGHT", -(10 - k) * 9, 0)
        f.chainBtn.gems[k] = g
    end
    f.chainBtn:SetScript("OnClick", function(self)
        if self.target then focus = self.target; peek = nil; lastWP = nil; Refresh(true) end
    end)
    f.chainBtn:SetScript("OnEnter", function(self)
        if not self.target then return end
        Tip():SetOwner(self, "ANCHOR_LEFT")
        Tip():AddLine(T("chainStart"))
        Tip():Show()
    end)
    f.chainBtn:SetScript("OnLeave", function() Tip():Hide() end)
    f.chainBtn:Hide()

    -- conseil (journal plein, pierre de foyer)
    f.advice = CreateFrame("Frame", nil, f); f.advice:SetSize(INNER, 16)
    f.advice.icon = f.advice:CreateTexture(nil, "ARTWORK"); f.advice.icon:SetSize(14, 14); f.advice.icon:SetPoint("TOPLEFT", 0, -1)
    f.advice.label = FS(f.advice, 11, COL.gold, FONT, "LEFT"); f.advice.label:SetPoint("TOPLEFT", 20, -2)
    f.advice.label:SetWidth(INNER - 20); if f.advice.label.SetWordWrap then f.advice.label:SetWordWrap(true) end
    f.advice:Hide()

    f.lockBtn = CreateFrame("Button", nil, f); f.lockBtn:SetSize(INNER, 16)
    if f.lockBtn.RegisterForClicks then f.lockBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    f.lockBtn.gem = Diamond(f.lockBtn, 6, COL.red); f.lockBtn.gem:SetPoint("LEFT", -1, 0)
    f.lockBtn.label = FS(f.lockBtn, 11, COL.accent, FONT, "LEFT"); f.lockBtn.label:SetPoint("TOPLEFT", 14, -2)
    f.lockBtn.label:SetWidth(INNER - 14); if f.lockBtn.label.SetWordWrap then f.lockBtn.label:SetWordWrap(true) end
    f.lockBtn.label:SetPoint("RIGHT")
    if f.lockBtn.label.SetWordWrap then f.lockBtn.label:SetWordWrap(false) end
    local lhl = Tex(f.lockBtn, COL.accent, 0.08, "HIGHLIGHT"); lhl:SetAllPoints()
    f.lockBtn:SetScript("OnClick", function(self, button)
        local i = self.idx
        if not i then return end
        if button == "RightButton" then
            DB.lockHide[steps[i].id] = true
            Refresh()
        else
            AskChain(steps[i].id)
        end
    end)
    f.lockBtn:SetScript("OnEnter", function(self)
        Tip():SetOwner(self, "ANCHOR_LEFT")
        Tip():AddLine(T("lockTitle"))
        for _, i in ipairs(self.list or {}) do
            local miss = {}
            for _, q in ipairs(blockedBy[i] or {}) do miss[#miss + 1] = (EST[q] and EST[q].n) or tostring(q) end
            Tip():AddLine((QName(steps[i]) or "?") .. "  |cff8c7f62(" .. table.concat(miss, ", ") .. ")|r", 0.84, 0.60, 0.40)
        end
        Tip():AddLine(T("lockTip"), 0.66, 0.60, 0.48, true)
        Tip():Show()
    end)
    f.lockBtn:SetScript("OnLeave", function() Tip():Hide() end)
    f.lockBtn:Hide()

    f.btnRow = CreateFrame("Frame", nil, f); f.btnRow:SetSize(INNER, 26)
    local prev = FlatButton(f.btnRow, 40, 26, function() Peek(-1) end); prev:SetPoint("LEFT"); prev:SetLabel("<")
    local nxt = FlatButton(f.btnRow, 40, 26, function() Peek(1) end); nxt:SetPoint("RIGHT"); nxt:SetLabel(">")
    f.skip = FlatButton(f.btnRow, INNER - 96, 26, Ignore); f.skip:SetPoint("CENTER")
    -- infobulles des boutons
    for _, bt in ipairs({ { prev, "btnPrevTip" }, { nxt, "btnNextTip" }, { f.skip, "btnOkTip" } }) do
        bt[1]:HookScript("OnEnter", function(self)
            Tip():SetOwner(self, "ANCHOR_BOTTOM"); Tip():AddLine(T(bt[2]), 1, 1, 1, true); Tip():Show()
        end)
        bt[1]:HookScript("OnLeave", function() Tip():Hide() end)
    end

    f.up = {}
    for k = 1, 4 do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(INNER, 16)
        local fs = FS(b, 11, COL.soft, FONT, "LEFT")
        fs:SetAllPoints()
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        b.fs = fs
        local h = Tex(b, COL.accent, 0.08, "HIGHLIGHT"); h:SetAllPoints()
        b:SetScript("OnClick", function(self)
            if self.idx then focus = self.idx; peek = nil; lastWP = nil; Refresh(true) end
        end)
        b:SetScript("OnEnter", function(self)
            Tip():SetOwner(self, "ANCHOR_LEFT")
            Tip():AddLine(T("clickGo"))
            local st = self.idx and steps and steps[self.idx]
            if st and st.t == "do" and type(st.id) == "number" and EST[st.id] then
                local e = Estimate({ st.id }, false)
                Tip():AddLine(T("estTip", FormatNum(e.xp), FormatNum(e.qxp), FormatNum(e.mxp), math.max(1, math.floor(e.secs / 60 + 0.5)), FormatNum(e.perHour)), 0.8, 0.73, 0.56, true)
            end
            Tip():Show()
        end)
        b:SetScript("OnLeave", function() Tip():Hide() end)
        b:Hide()
        f.up[k] = b
    end

    f:SetShown(DB.shown ~= false)
    if f.SetScale then f:SetScale(DB.scale or 1) end
end

------------------------------------------------------------------
-- Ce que la fenetre d'options (Options.lua) utilise du moteur
------------------------------------------------------------------
ns.E = {
    T = T, Title = Title, Lang = Lang, say = say, Refresh = Refresh, SetGuide = SetGuide,
    StartDungeon = StartDungeon, StopDungeon = StopDungeon, ClearWaypoint = ClearWaypoint,
    AutoPick = AutoPick, AllDone = AllDone,
    ClassQuestList = function() return ClassQuestList() end, PlaceWaypointAgain = function() if steps and current and steps[current] then pcall(SetWaypoint, steps[current]) end end, StyleGet = function() return StyleGet() end,
    ApplyPreset = function(n) local ok, err = pcall(ApplyPreset, n); if not ok then say(T("errInternal", tostring(err))) end end, StyleChanged = function() styleCache = nil; local ok, err = pcall(Advance); if not ok then say(T("errInternal", tostring(err))) end; Refresh(true) end, AskClass = function(q) AskChain(q, true) end, ChronShow = function(k) ChronShow(k) end,
    Guides = Guides, ICON = ICON, VERSION = VERSION, CHECK = CHECK,
    MAIN_ORDER = MAIN_ORDER, IS_DUNGEON = IS_DUNGEON, DUNGEONS = DUNGEONS, MINLVL = MINLVL, MAXLVL = MAXLVL,
    DB = function() return DB end,
    Frame = function() return f end,
    Guide = function() return G end,
    Steps = function() return steps end,
    Current = function() return current end,
    Race = function() return myRace end,
    ResetWP = function() lastWP = nil end,
    WarpathName = WarpathName,
    Tip = function() return Tip() end, GuideStatus = function(k) return GuideStatus(k) end,
    ProfOrder = function() return PROF_ORDER end, ProfKey = function(id) return PROF_KEY[id] end, ProfName = function(id) return ProfName(id) end, TrainerPins = function() if TrainerPinsRefresh then pcall(TrainerPinsRefresh, true) end end,
    ProfQuestList = function() return ProfQuestList() end, ProfOn = function(id) return ProfOn(id) end,
    ProfSet = function(id, v) ProfSet(id, v) end, ProfDetect = function() return ProfDetect(true) end,
    AskProf = function(q) AskChain(q, true, "prof") end,
    Kit = { COL = COL, FONT = FONT, DISPLAY = DISPLAY, Caps = Caps, Upper = Upper, Spaced = Spaced, FS = FS, Tex = Tex,
            Diamond = Diamond, Divider = Divider, TitledRule = TitledRule, FlatButton = FlatButton },
}
ns.UI = ns.UI or {}

------------------------------------------------------------------
-- Carte de vol : apprendre les trajets connus et surligner la destination
------------------------------------------------------------------
taxiGlow = nil

function NodeKeyFor(name)
    if not name then return nil end
    for _, n in ipairs(FLIGHTS) do
        if name:find(n.key, 1, true) then return n.key end
    end
end

function OnTaxiOpened()
    if not NumTaxiNodes then return end
    DB.fp = DB.fp or {}
    DB.fpLinks = DB.fpLinks or {}
    local target, here
    local reach = {}
    for i = 1, NumTaxiNodes() do
        local name = TaxiNodeName and TaxiNodeName(i)
        local kind = TaxiNodeGetType and TaxiNodeGetType(i)
        local key = NodeKeyFor(name)
        if key then
            -- CURRENT = ici ; REACHABLE = connu et atteignable ; DISTANT = connu mais pas relie d'ici
            if kind == "CURRENT" or kind == "REACHABLE" or kind == "DISTANT" then DB.fp[key] = true end
            if kind == "CURRENT" then here = key; ns.Comfort.SetTaxiFrom(name) end
            if kind == "REACHABLE" then reach[key] = true end
        end
        if flightPlan and key == flightPlan.to.key and kind == "REACHABLE" then target = i end
    end
    if here then DB.fpLinks[here] = reach end
    if target then
        local btn = _G["TaxiButton" .. target]
        if btn then
            if not taxiGlow then
                taxiGlow = CreateFrame("Frame", nil, UIParent)
                taxiGlow:SetSize(44, 44)
                local t = taxiGlow:CreateTexture(nil, "OVERLAY")
                t:SetAllPoints()
                t:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
                t:SetBlendMode("ADD")
                t:SetVertexColor(0.2, 1, 0.3)
                taxiGlow.tex = t
                local elapsed = 0
                taxiGlow:SetScript("OnUpdate", function(self, dt)
                    elapsed = elapsed + (dt or 0)
                    self.tex:SetAlpha(0.55 + 0.45 * math.sin(elapsed * 5))
                end)
            end
            taxiGlow:SetParent(btn)
            taxiGlow:ClearAllPoints()
            taxiGlow:SetPoint("CENTER", btn, "CENTER")
            taxiGlow:SetFrameLevel((btn:GetFrameLevel() or 1) + 5)
            taxiGlow:Show()
        end
        say(T("flyTo", flightPlan.to.name))
        if DB.autoFly ~= false and not (IsShiftKeyDown and IsShiftKeyDown()) and TakeTaxiNode then
            local node = target
            if C_Timer and C_Timer.After then C_Timer.After(0.4, function() if TaxiFrame and TaxiFrame:IsShown() or (TaxiNodeName and TaxiNodeName(node)) then ns.Trace("TakeTaxiNode"); TakeTaxiNode(node) end end) else ns.Trace("TakeTaxiNode"); TakeTaxiNode(node) end
        end
    end
    Refresh(true)
end

function OnTaxiClosed()
    if taxiGlow then taxiGlow:Hide() end
end

------------------------------------------------------------------
-- La fleche reste en place : si le jeu efface le waypoint a l'arrivee (ex. au maitre de vol),
-- on le remet des que tu t'en eloignes un peu, tant que le guide en a encore besoin.
------------------------------------------------------------------
wpTicker = CreateFrame("Frame")
wpElapsed = 0
distElapsed = 0
wpTicker:SetScript("OnUpdate", function(_, dt)
    distElapsed = distElapsed + (dt or 0)
    if distElapsed >= 0.5 then distElapsed = 0; UpdateDistance() end
    wpElapsed = wpElapsed + (dt or 0)
    if wpElapsed < 1 then return end
    wpElapsed = 0
    if DB then pcall(LearnGates) end
    if not (DB and DB.wp and desiredWP) then return end
    if not (C_Map and C_Map.HasUserWaypoint) or C_Map.HasUserWaypoint() then return end
    if UnitOnTaxi and UnitOnTaxi("player") then return end
    local me = PlayerWP()
    local w = WP(desiredWP.m, desiredWP.x, desiredWP.y)
    local d = me and w and me[3] == w[3] and Dist(me[1], me[2], w[1], w[2])
    if not d or d > 12 then PlaceNative(desiredWP) end
end)
