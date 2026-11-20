-- Oghoule's Warpath : fenetre d'options (onglets), bouton de minimap, panneau des options de Blizzard
local ADDON, ns = ...
local E = ns.E
local ui = ns.UI
local T, Title, Lang, say, Refresh, SetGuide = E.T, E.Title, E.Lang, E.say, E.Refresh, E.SetGuide
local StartDungeon, StopDungeon, ClearWaypoint, AutoPick, AllDone = E.StartDungeon, E.StopDungeon, E.ClearWaypoint, E.AutoPick, E.AllDone
local Guides, ICON, VERSION = E.Guides, E.ICON, E.VERSION
local MAIN_ORDER, IS_DUNGEON, DUNGEONS, MINLVL, MAXLVL = E.MAIN_ORDER, E.IS_DUNGEON, E.DUNGEONS, E.MINLVL, E.MAXLVL
local K = E.Kit
local COL, FONT, Caps, FS, Tex, Diamond, Divider, FlatButton = K.COL, K.FONT, K.Caps, K.FS, K.Tex, K.Diamond, K.Divider, K.FlatButton
-- DB est recree au chargement : on passe toujours par la table du moteur
local DB = setmetatable({}, {
    __index = function(_, k) local d = E.DB(); return d and d[k] end,
    __newindex = function(_, k, v) E.DB()[k] = v end,
})

local opt, mm
local showHooks = {}
local optRows = {}   -- fonctions qui remettent l'etat des controles
local locRows = {}   -- textes re-appliques quand on change de langue
local function Loc(fn) locRows[#locRows + 1] = fn; fn() end

local function GuideRange(key)
    local d = IS_DUNGEON[key]
    if d then return d.min, d.max end
    return MINLVL[key] or 1, MAXLVL[key] or 60
end

local function ZoneName(key)
    local g = Guides[key]
    if not g then return key end
    return (Title(g):gsub("%s*%b()", ""):gsub("%s+%d+%-%d+$", ""))
end

local statusCache = {}
local function GuideState(key)
    if not E.Race() then return nil end
    if statusCache[key] == nil then
        local ok, st = pcall(E.GuideStatus, key)
        statusCache[key] = (ok and st) or false
    end
    return statusCache[key] or nil
end

local function RefreshOptions()
    if not opt or not opt:IsShown() then return end
    for _, fn in ipairs(locRows) do fn() end
    for _, fn in ipairs(optRows) do fn() end
end

------------------------------------------------------------------
-- Controles
------------------------------------------------------------------
local ROW_H = 24

-- Ligne a choix unique : losange plein quand elle est choisie
local function ChoiceRow(parent, w, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, ROW_H)
    local top = Tex(b, COL.faint); top:SetHeight(1); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); b.top = top
    local hl = Tex(b, COL.accent, 0.07, "HIGHLIGHT"); hl:SetAllPoints()
    b.gem = Diamond(b, 7, COL.line, true); b.gem:SetPoint("LEFT", 2, 0)
    b.status = FS(b, 9, COL.gold, FONT, "RIGHT"); b.status:SetPoint("RIGHT", -2, 0)
    b.label = FS(b, 12, COL.white, FONT, "LEFT"); b.label:SetPoint("LEFT", 20, 0); b.label:SetPoint("RIGHT", b.status, "LEFT", -6, 0)
    if b.label.SetWordWrap then b.label:SetWordWrap(false) end
    function b:SetChecked(v)
        self.checked = v and true or false
        self.gem:SetStyle(v and COL.red or COL.line, not v)
        if self.label.SetTextColor then local c = v and COL.white or COL.soft; self.label:SetTextColor(c[1], c[2], c[3]) end
    end
    b:SetChecked(false)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        if not self.tipKey then return end
        E.Tip():SetOwner(self, "ANCHOR_RIGHT"); E.Tip():AddLine(T("stLow")); E.Tip():AddLine(T(self.tipKey), 1, 1, 1, true); E.Tip():Show()
    end)
    b:SetScript("OnLeave", function() E.Tip():Hide() end)
    return b
end

-- Case a cocher : petit carre, plein quand c'est actif
local function CheckRow(parent, w, key, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, ROW_H)
    local hl = Tex(b, COL.accent, 0.07, "HIGHLIGHT"); hl:SetAllPoints()
    -- case oui/non : losange a contour dore (le losange plein seul = choix unique)
    b.mark = K.DiamondCheck(b, 11); b.mark:SetPoint("LEFT", -2, 0)
    b.label = FS(b, 12, COL.white, FONT, "LEFT"); b.label:SetPoint("LEFT", 22, 0)
    Loc(function() b.label:SetText(T(key)) end)
    function b:SetChecked(v)
        self.checked = v and true or false; self.mark:SetOn(self.checked)
        if self.label.SetTextColor then local c = self.checked and COL.white or COL.soft; self.label:SetTextColor(c[1], c[2], c[3]) end
    end
    function b:GetChecked() return self.checked end
    b:SetScript("OnClick", function(self) self:SetChecked(not self.checked); set(self.checked) end)
    b:SetScript("OnEnter", function(self)
        local tip = T(key .. "Tip")
        if tip and tip ~= key .. "Tip" then
            E.Tip():SetOwner(self, "ANCHOR_RIGHT"); E.Tip():AddLine(T(key)); E.Tip():AddLine(tip, 1, 1, 1, true); E.Tip():Show()
        end
    end)
    b:SetScript("OnLeave", function() E.Tip():Hide() end)
    optRows[#optRows + 1] = function() b:SetChecked(get()) end
    b:SetChecked(get())
    return b
end

local function SmallHeader(parent, key)
    local h = FS(parent, 9, COL.gold, FONT, "LEFT")
    Loc(function() h:SetText(Caps(T(key))) end)
    return h
end

local function SetLang(l)
    DB.lang = l
    if WarpathDropDB then WarpathDropDB._lang = l end
    say(T("langSet"))
    if E.Frame() then Refresh(true) end
    RefreshOptions()
end

local function MinimapPos()
    if not mm then return end
    local a = math.rad(DB.mmAngle or 225)
    local r = (Minimap:GetWidth() / 2) + 6
    mm:ClearAllPoints()
    mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

------------------------------------------------------------------
-- Fenetre d'options
------------------------------------------------------------------
local OW, OH, OPAD, NAVW = 790, 600, 34, 200
local CW = OW - NAVW - 20 - OPAD

local showTabFn
local function CreateOptions()
    if opt then return end
    opt = CreateFrame("Frame", "WarpathOptions", UIParent)
    opt:SetSize(OW, OH)
    opt:SetPoint("CENTER")
    opt:SetFrameStrata("DIALOG")
    local bg = Tex(opt, COL.bg, 0.95, "BACKGROUND"); bg:SetAllPoints()
    K.Border(opt, COL.line, 0.8, "BORDER")
    -- en-tete comme la fenetre du guide : bande plus claire, losange rouge, nom a gauche
    -- v1.41 (uniformisation) : en-tete standard de 34 px, comme le guide
    local HH = 34
    local hbg = Tex(opt, COL.panel, 0.95, "BORDER"); hbg:SetHeight(HH); hbg:SetPoint("TOPLEFT", 1, -1); hbg:SetPoint("TOPRIGHT", -1, -1)
    local hln = Tex(opt, COL.line, 1, "ARTWORK"); hln:SetHeight(1); hln:SetPoint("TOPLEFT", 0, -HH); hln:SetPoint("TOPRIGHT", 0, -HH)
    local hgem = Diamond(opt, 8, COL.red); hgem:SetPoint("LEFT", opt, "TOPLEFT", 14, -HH / 2)
    opt:SetMovable(true)
    opt:EnableMouse(true)
    opt:RegisterForDrag("LeftButton")
    opt:SetScript("OnDragStart", opt.StartMoving)
    opt:SetScript("OnDragStop", opt.StopMovingOrSizing)
    opt:SetClampedToScreen(true)
    opt:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, "WarpathOptions") end

    -- fermer : petit bouton carre 16 px, comme le « - » du guide
    local close = K.HeadButton(opt, "x")
    close:SetPoint("RIGHT", opt, "TOPRIGHT", -6, -HH / 2)
    close:SetScript("OnClick", function() opt:Hide() end)

    local name = FS(opt, 12, COL.white, FONT, "LEFT")
    name:SetPoint("LEFT", opt, "TOPLEFT", 30, -HH / 2)
    optRows[#optRows + 1] = function() name:SetText(Caps(E.WarpathName() .. " · " .. T("optTitle"))) end
    -- poignee : taille de la fenetre d'options (a part de celle du guide)
    K.ScaleGrip(opt, function() return DB.optScale or 1 end, function(v) DB.optScale = v end)
    local ver = FS(opt, 9, COL.faint, FONT, "LEFT"); ver:SetPoint("BOTTOMLEFT", 24, 16)
    ver:SetText(Caps("Oghoule's Warpath") .. "   v" .. VERSION)
    if ver.SetTextColor then ver:SetTextColor(COL.line[1], COL.line[2], COL.line[3]) end

    -- Signaler un probleme (= /warpath bug) : une note facultative, puis Entree
    do
        local note = CreateFrame("EditBox", nil, opt)
        note:SetSize(NAVW - 44, 22); note:SetPoint("BOTTOMLEFT", 24, 70)
        note:SetAutoFocus(false); note:SetMaxLetters(120)
        if note.SetFontObject then note:SetFontObject(ChatFontNormal) end
        if note.SetFont then pcall(note.SetFont, note, FONT, 11, "") end
        if note.SetTextInsets then note:SetTextInsets(6, 6, 0, 0) end
        local nbg = Tex(note, COL.bg, 1, "BACKGROUND"); nbg:SetAllPoints()
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local t = Tex(note, COL.line)
            if side == "TOP" or side == "BOTTOM" then t:SetHeight(1); t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
            else t:SetWidth(1); t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side) end
        end
        local hint = FS(note, 10, COL.faint, FONT, "LEFT"); hint:SetPoint("LEFT", 6, 0)
        Loc(function() hint:SetText(T("bugNoteHint")) end)
        note:Hide()
        local bug
        local function send()
            local t = (note:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
            SlashCmdList.WARPATH("bug" .. (t ~= "" and (" " .. t) or ""))
            note:SetText(""); note:ClearFocus(); note:Hide()
            bug:SetLabel(K.Upper(T("bugBtn")))
        end
        note:SetScript("OnTextChanged", function(self) hint:SetShown((self:GetText() or "") == "") end)
        note:SetScript("OnEnterPressed", send)
        note:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus(); self:Hide(); bug:SetLabel(K.Upper(T("bugBtn"))) end)
        bug = FlatButton(opt, NAVW - 44, 24, function(self)
            if E.BugWindow then E.BugWindow(); return end
            if note:IsShown() then send() else note:Show(); note:SetFocus(); self:SetLabel(K.Upper(T("bugSend"))) end
        end)
        bug:SetPoint("BOTTOMLEFT", 24, 40)
        Loc(function() bug:SetLabel(K.Upper(note:IsShown() and T("bugSend") or T("bugBtn"))) end)
        bug:SetScript("OnEnter", function(self)
            E.Tip():SetOwner(self, "ANCHOR_RIGHT"); E.Tip():AddLine(T("bugBtn")); E.Tip():AddLine(T("bugBtnTip"), 1, 1, 1, true); E.Tip():Show()
        end)
        bug:SetScript("OnLeave", function() E.Tip():Hide() end)
    end

    -- Onglets
    local tabs, pages = {}, {}
    local function ShowTab(k)
        if not pages[k] then k = 1 end
        DB.optTab = k
        for j, tb in ipairs(tabs) do
            local on = (j == k)
            pages[j]:SetShown(on)
            tb.line:SetShown(on); tb.sel:SetShown(on)
            local c = on and COL.white or COL.gold
            if tb.fs.SetTextColor then tb.fs:SetTextColor(c[1], c[2], c[3]) end
        end
    end
    -- navigation laterale (ordre d'affichage) ; les numeros de pages restent ceux du code ci-dessous
    local TABS = { "tabCampaign", "tabDungeons", "tabClass", "tabStyle", "tabRoute", "tabDisplay", "tabAuto", "tabProf" }
    local ORDER = { 1, 4, 2, 3, 8, 5, 7, 6 }
    local navLine = Tex(opt, COL.faint); navLine:SetWidth(1)
    navLine:SetPoint("TOPLEFT", NAVW + 10, -58); navLine:SetPoint("BOTTOMLEFT", NAVW + 10, 34)
    for pos, k in ipairs(ORDER) do
        local key = TABS[k]
        local tb = CreateFrame("Button", nil, opt)
        tb:SetSize(NAVW - 20, 32)
        tb:SetPoint("TOPLEFT", 20, -62 - (pos - 1) * 36)
        tb.sel = Tex(tb, COL.panel, 1, "BACKGROUND"); tb.sel:SetAllPoints()
        local hl = Tex(tb, COL.accent, 0.06, "HIGHLIGHT"); hl:SetAllPoints()
        tb.fs = FS(tb, 10, COL.gold, FONT, "LEFT"); tb.fs:SetPoint("LEFT", 14, 0)
        Loc(function() tb.fs:SetText(Caps(T(key))) end)
        tb.line = Tex(tb, COL.red); tb.line:SetWidth(2); tb.line:SetPoint("TOPLEFT"); tb.line:SetPoint("BOTTOMLEFT")
        tb:SetScript("OnClick", function() ShowTab(k) end)
        tb:SetScript("OnEnter", function(self)
            local tip = T(key .. "Tip")
            if tip ~= key .. "Tip" then E.Tip():SetOwner(self, "ANCHOR_RIGHT"); E.Tip():AddLine(tip, 1, 1, 1, true); E.Tip():Show() end
        end)
        tb:SetScript("OnLeave", function() E.Tip():Hide() end)
        tabs[k] = tb
        local pg = CreateFrame("Frame", nil, opt)
        pg:SetPoint("TOPLEFT", NAVW + 30, -62)
        pg:SetPoint("BOTTOMRIGHT", -OPAD, 34)
        pages[k] = pg
    end

    -- 1. Campagne : zone a faire / zone suivante / langue
    do
        local pg = pages[1]
        local colW = math.floor((CW - 24) / 2)
        local h1 = SmallHeader(pg, "chapters"); h1:SetPoint("TOPLEFT", 0, 0)
        local h2 = SmallHeader(pg, "nextZone"); h2:SetPoint("TOPLEFT", colW + 24, 0)
        local y = -16
        local auto = ChoiceRow(pg, colW, function()
            DB.manual = nil
            local k = AutoPick()
            if k then SetGuide(k) end
            RefreshOptions()
        end)
        auto:SetPoint("TOPLEFT", 0, y)
        optRows[#optRows + 1] = function()
            auto:SetChecked(not DB.manual and not IS_DUNGEON[DB.guide])
            auto.label:SetText(T("auto"))
            local g = DB.guide
            auto.status:SetText((not DB.manual and g and Guides[g] and not IS_DUNGEON[g]) and ZoneName(g) or "")
        end
        local nauto = ChoiceRow(pg, colW, function() DB.nextGuide = nil; RefreshOptions() end)
        nauto:SetPoint("TOPLEFT", colW + 24, y)
        optRows[#optRows + 1] = function() nauto:SetChecked(DB.nextGuide == nil); nauto.label:SetText(T("auto")) end
        y = y - ROW_H
        -- liste paginee (il y a maintenant plus de 30 zones)
        local PER = 11
        local list = {}
        for _, key in ipairs(MAIN_ORDER) do if Guides[key] then list[#list + 1] = key end end
        local pages = math.max(1, math.ceil(#list / PER))
        local page
        local cur, nxt = {}, {}
        for k = 1, PER do
            local slotY = y - (k - 1) * ROW_H
            local b = ChoiceRow(pg, colW, function(self)
                if not self.key then return end
                DB.manual = true
                SetGuide(self.key)
                RefreshOptions()
            end)
            b:SetPoint("TOPLEFT", 0, slotY)
            local nb = ChoiceRow(pg, colW, function(self)
                if not self.key then return end
                DB.nextGuide = self.key
                RefreshOptions()
            end)
            nb:SetPoint("TOPLEFT", colW + 24, slotY)
            cur[k], nxt[k] = b, nb
        end
        y = y - PER * ROW_H - 4
        local pageLbl = FS(pg, 9, COL.gold, FONT, "CENTER"); pageLbl:SetWidth(120)
        pageLbl:SetPoint("TOP", pg, "TOP", 0, y - 7)
        local prevB = FlatButton(pg, 28, 22, function() page = math.max(1, page - 1); RefreshOptions() end)
        prevB:SetPoint("TOPRIGHT", pageLbl, "TOPLEFT", -6, 5); prevB:SetLabel("<")
        local nextB = FlatButton(pg, 28, 22, function() page = math.min(pages, page + 1); RefreshOptions() end)
        nextB:SetPoint("TOPLEFT", pageLbl, "TOPRIGHT", 6, 5); nextB:SetLabel(">")
        showHooks[#showHooks + 1] = function()
            page = 1
            for i, key in ipairs(list) do if key == DB.guide then page = math.ceil(i / PER) end end
        end
        page = 1
        optRows[#optRows + 1] = function()
            pageLbl:SetText(Caps(T("pageLbl", page, pages)))
            for k = 1, PER do
                local key = list[(page - 1) * PER + k]
                local b, nb = cur[k], nxt[k]
                b.key, nb.key = key, key
                b:SetShown(key ~= nil); nb:SetShown(key ~= nil)
                if key then
                    local lo, hi = GuideRange(key)
                    b:SetChecked(DB.manual and DB.guide == key)
                    b.label:SetText(ZoneName(key))
                    local st = GuideState(key)
                    local txt = (st == "done" and ("|cff9cc7a8" .. Caps(T("stDone")) .. "|r"))
                        or (st == "low" and ("|cff8c7f62" .. Caps(T("stLow")) .. "|r")) or (lo .. " - " .. hi)
                    b.status:SetText(txt)
                    b.tipKey = (st == "low") and "stLowTip" or nil
                    nb:SetChecked(DB.nextGuide == key)
                    nb.label:SetText(ZoneName(key))
                    nb.status:SetText(st == "low" and ("|cff8c7f62" .. Caps(T("stLow")) .. "|r") or (lo .. " - " .. hi))
                    nb.tipKey = b.tipKey
                end
            end
        end
        y = y - 26
        local bottom = Tex(pg, COL.faint); bottom:SetHeight(1)
        bottom:SetPoint("TOPLEFT", 0, y); bottom:SetPoint("TOPRIGHT", pg, "TOPRIGHT", 0, y)
        -- langue
        y = y - 34
        local lh = SmallHeader(pg, "language"); lh:SetPoint("TOPLEFT", 0, y - 8)
        local rfr = ChoiceRow(pg, 130, function() SetLang("fr") end); rfr:SetPoint("TOPLEFT", 150, y)
        local ren = ChoiceRow(pg, 130, function() SetLang("en") end); ren:SetPoint("TOPLEFT", 310, y)
        rfr.label:SetText("Français"); ren.label:SetText("English")
        optRows[#optRows + 1] = function() rfr:SetChecked(Lang() == "fr"); ren:SetChecked(Lang() == "en") end
    end

    -- 2. Donjons
    do
        local pg = pages[2]
        local h = SmallHeader(pg, "dungeons"); h:SetPoint("TOPLEFT", 0, 0)
        local y, n, BW = -18, 0, math.floor((CW - 8) / 2)
        for _, d in ipairs(DUNGEONS) do
            if Guides[d.key] then
                local col, row = n % 2, math.floor(n / 2)
                n = n + 1
                local b = FlatButton(pg, BW, 23, function() StartDungeon(d.key); RefreshOptions() end)
                b:SetPoint("TOPLEFT", col * (BW + 8), y - row * 26)
                b.fs:ClearAllPoints(); b.fs:SetPoint("LEFT", 10, 0)
                b.fs:SetText(d.name)
                if b.fs.SetFont then b.fs:SetFont(FONT, 10, "") end
                local lv = FS(b, 9, COL.gold, FONT, "RIGHT"); lv:SetPoint("RIGHT", -10, 0)
                -- v1.42 : le nom s'arrete avant les niveaux (coupe en « ... » si trop long)
                b.fs:SetPoint("RIGHT", lv, "LEFT", -6, 0); b.fs:SetJustifyH("LEFT")
                if b.fs.SetWordWrap then b.fs:SetWordWrap(false) end
                optRows[#optRows + 1] = function()
                    local me = UnitLevel and UnitLevel("player") or 0
                    local inRange = me >= d.min and me <= d.max
                    local ideal = DungeonIdeal and DungeonIdeal(d.key)
                    lv:SetText((inRange and "|cffcdbb8e" or "") .. d.min .. "-" .. d.max .. (inRange and "|r" or "")
                        .. (ideal and ("  |cff8c7f62·|r " .. ((me >= ideal and inRange) and "|cffcdbb8e" or "") .. ideal .. ((me >= ideal and inRange) and "|r" or "")) or ""))
                    local active = (DB.guide == d.key)
                    local c = active and COL.accent or COL.white
                    if b.fs.SetTextColor then b.fs:SetTextColor(c[1], c[2], c[3]) end
                end
                b:SetScript("OnEnter", function(self)
                    E.Tip():SetOwner(self, "ANCHOR_RIGHT")
                    E.Tip():AddLine(d.name)
                    E.Tip():AddLine(T("dTip", d.min, d.max), 1, 1, 1, true)
                    local ideal = DungeonIdeal and DungeonIdeal(d.key)
                    if ideal then E.Tip():AddLine(T("dIdeal", ideal), 0.84, 0.72, 0.4, true) end
                    E.Tip():Show()
                end)
                b:SetScript("OnLeave", function() E.Tip():Hide() end)
            end
        end
        y = y - math.ceil(n / 2) * 26
        y = y - 6
        local ask = CheckRow(pg, CW, "askDungeons", function() return not DB.noDungeonAsk end, function(v) DB.noDungeonAsk = not v end)
        ask:SetPoint("TOPLEFT", 0, y)
        local stop = FlatButton(pg, 200, 28, function() StopDungeon(); RefreshOptions() end)
        stop:SetPoint("TOPLEFT", 0, y - 32)
        Loc(function() stop:SetLabel(Caps(T("leaveDungeon"))) end)
    end

    -- 3. Classe : quetes de classe importantes (la variante de ta race)
    do
        local pg = pages[3]
        local h = SmallHeader(pg, "tabClass"); h:SetPoint("TOPLEFT", 0, 0)
        local rows = {}
        for k = 1, 12 do
            local b = FlatButton(pg, CW, 26, function(self) if self.q then E.AskClass(self.q) end end)
            b:SetPoint("TOPLEFT", 0, -18 - (k - 1) * 30)
            b.fs:ClearAllPoints(); b.fs:SetPoint("LEFT", 12, 0)
            if b.fs.SetFont then b.fs:SetFont(FONT, 11, "") end
            b.lv = FS(b, 9, COL.gold, FONT, "RIGHT"); b.lv:SetPoint("RIGHT", -12, 0)
            rows[k] = b
        end
        local none = FS(pg, 11, COL.soft, FONT, "LEFT"); none:SetWidth(CW); none:SetPoint("TOPLEFT", 0, -22)
        local ask = CheckRow(pg, CW, "askClass", function() return not DB.noClassAsk end, function(v) DB.noClassAsk = not v end)
        ask:SetPoint("TOPLEFT", 0, -18 - 3 * 30 - 10)
        optRows[#optRows + 1] = function()
            local list = E.ClassQuestList()
            local me = UnitLevel and UnitLevel("player") or 0
            none:SetText(#list == 0 and T("classNone") or ""); none:SetShown(#list == 0)
            ask:ClearAllPoints(); ask:SetPoint("TOPLEFT", 0, -18 - math.max(1, math.min(#list, 12)) * 30 - 12)
            for k, b in ipairs(rows) do
                local c = list[k]
                if c then
                    b.q = (not c.done) and c.q or nil
                    b.fs:SetText(c.name)
                    local col = c.done and COL.gold or (me >= c.lvl and COL.white or COL.soft)
                    if b.fs.SetTextColor then b.fs:SetTextColor(col[1], col[2], col[3]) end
                    b.lv:SetText(c.done and T("classDone") or (c.lvl2 > c.lvl and T("classLvls", c.lvl, c.lvl2) or T("classLvl", c.lvl)))
                    b:Show()
                else
                    b.q = nil; b:Hide()
                end
            end
        end
    end

    -- 8. Metiers : cocher ses metiers, voir leurs quetes
    do
        local pg = pages[8]
        local h = SmallHeader(pg, "tabProf"); h:SetPoint("TOPLEFT", 0, 0)
        local half = math.floor((CW - 12) / 2)
        for k, id in ipairs(E.ProfOrder() or {}) do
            local key = E.ProfKey(id)
            local row = CheckRow(pg, half, key, function() return E.ProfOn(id) end, function(v) E.ProfSet(id, v); E.TrainerPins() end)
            Loc(function() row.label:SetText(E.ProfName(id)) end)
            row:SetPoint("TOPLEFT", ((k - 1) % 2) * (half + 12), -18 - math.floor((k - 1) / 2) * ROW_H)
        end
        local y = -18 - 6 * ROW_H - 6
        local ask = CheckRow(pg, CW, "askProf", function() return not DB.noProfAsk end, function(v) DB.noProfAsk = not v end)
        ask:SetPoint("TOPLEFT", 0, y); y = y - ROW_H
        local tp = CheckRow(pg, CW, "trainerOpt", function() return DB.trainerPins ~= false end, function(v) DB.trainerPins = v; E.TrainerPins() end)
        tp:SetPoint("TOPLEFT", 0, y); y = y - ROW_H - 8
        local h2 = SmallHeader(pg, "profListHdr"); h2:SetPoint("TOPLEFT", 0, y); y = y - 18
        local none = FS(pg, 11, COL.soft, FONT, "LEFT"); none:SetWidth(CW); none:SetPoint("TOPLEFT", 0, y - 4)
        local rows = {}
        for k = 1, 6 do
            local b = FlatButton(pg, CW, 24, function(self) if self.q then E.AskProf(self.q) end end)
            b:SetPoint("TOPLEFT", 0, y - (k - 1) * 28)
            b.fs:ClearAllPoints(); b.fs:SetPoint("LEFT", 12, 0)
            if b.fs.SetFont then b.fs:SetFont(FONT, 11, "") end
            b.lv = FS(b, 9, COL.gold, FONT, "RIGHT"); b.lv:SetPoint("RIGHT", -12, 0)
            rows[k] = b
        end
        optRows[#optRows + 1] = function()
            local all, me = E.ProfQuestList(), UnitLevel and UnitLevel("player") or 0
            local list = {}
            -- une meme quete existe en plusieurs exemplaires (une par ville de depart) : on la montre une fois
            local seen = {}
            for _, c in ipairs(all) do
                local key = (c.name or "") .. ":" .. tostring(c.s)
                if not c.done and c.l + 6 >= me and not seen[key] then seen[key] = true; list[#list + 1] = c end
            end
            none:SetText(#list == 0 and T("profNone") or ""); none:SetShown(#list == 0)
            for k, b in ipairs(rows) do
                local c = list[k]
                if c then
                    b.q = c.q
                    local tag = c.spec and T("profSpec") or (c.dungeon and T("profDungeon") or "")
                    b.fs:SetText(c.name .. tag)
                    local col = (me >= c.r and c.rank) and COL.white or COL.soft
                    if b.fs.SetTextColor then b.fs:SetTextColor(col[1], col[2], col[3]) end
                    b.lv:SetText(T("profLvl", c.r, c.m))
                    b:Show()
                else
                    b.q = nil; b:Hide()
                end
            end
        end
    end

    -- 4. Style de jeu (tous les guides 1-60)
    do
        local pg = pages[4]
        local h = SmallHeader(pg, "tabStyle"); h:SetPoint("TOPLEFT", 0, 0)
        local y = -20
        -- prereglages
        local pl = FS(pg, 10, COL.gold, FONT, "LEFT"); pl:SetPoint("TOPLEFT", 0, y - 8)
        Loc(function() pl:SetText(Caps(T("presets"))) end)
        local PW = math.floor((CW - 140) / 4) - 6
        for k, p in ipairs({ "solo", "group", "calm", "safe" }) do
            local b = FlatButton(pg, PW, 26, function() E.ApplyPreset(p); RefreshOptions() end)
            b:SetPoint("TOPLEFT", 140 + (k - 1) * (PW + 6), y)
            Loc(function() b:SetLabel(Caps(T("preset_" .. p))) end)
            if b.fs.SetFont then b.fs:SetFont(FONT, 9, "") end
        end
        y = y - 44
        local CHW = math.floor((CW - 140) / 3) - 4
        local function Group(labelKey, field, choices)
            local lab = FS(pg, 10, COL.gold, FONT, "LEFT"); lab:SetPoint("TOPLEFT", 0, y - 8); lab:SetWidth(136)
            Loc(function() lab:SetText(Caps(T(labelKey))) end)
            for k, ch in ipairs(choices) do
                local r = ChoiceRow(pg, CHW, function() E.StyleGet()[field] = ch; RefreshOptions(); E.StyleChanged() end)
                r:SetPoint("TOPLEFT", 140 + (k - 1) * (CHW + 4), y); r.top:Hide()
                Loc(function() r.label:SetText(T("st_" .. field .. "_" .. ch)) end)
                optRows[#optRows + 1] = function() r:SetChecked(E.StyleGet()[field] == ch) end
            end
            y = y - ROW_H - 18
        end
        Group("stElite", "elite", { "always", "group", "never" })
        Group("stXp", "xpMode", { "farm", "dungeon", "both" })
        Group("stPrio", "prio", { "balanced", "xp", "travel" })
        local es = CheckRow(pg, CW, "stEscort", function() return E.StyleGet().noEscort end,
            function(v) E.StyleGet().noEscort = v and true or nil; E.StyleChanged() end)
        es:SetPoint("TOPLEFT", 0, y)
        local pr = CheckRow(pg, CW, "stPrudent", function() return E.StyleGet().prudent end,
            function(v) E.StyleGet().prudent = v and true or nil; E.StyleChanged() end)
        pr:SetPoint("TOPLEFT", 0, y - ROW_H)
        local note = FS(pg, 10, COL.soft, FONT, "LEFT"); note:SetWidth(CW); note:SetPoint("TOPLEFT", 0, y - 2 * ROW_H - 14)
        Loc(function() note:SetText(T("stNote")) end)
    end

    -- 3. Itineraire
    do
        -- v1.41 (audit, point 8) : trois sections : Fleche · Trajets et vols · Ciblage
        local pg = pages[5]
        local y = 0
        local function sec(key) local h = SmallHeader(pg, key); h:SetPoint("TOPLEFT", 0, y); y = y - 18 end
        local function row(r) r:SetPoint("TOPLEFT", 0, y); y = y - ROW_H end
        -- FLECHE
        sec("secArrow")
        row(CheckRow(pg, CW, "arrow", function() return DB.wp end,
            function(v) DB.wp = v; if not v then ClearWaypoint() end; E.ResetWP(); Refresh(true) end))
        row(CheckRow(pg, CW, "arrowOwn", function() return DB.ownArrow ~= false end,
            function(v) DB.ownArrow = v; E.PlaceWaypointAgain() end))
        row(CheckRow(pg, CW, "gameWP", function() return DB.gameWP ~= false end,
            function(v) DB.gameWP = v; E.PlaceWaypointAgain() end))
        row(CheckRow(pg, CW, "mmPin", function() return DB.mmPin ~= false end, function(v) DB.mmPin = v end))
        local sl = FS(pg, 10, COL.gold, FONT, "LEFT"); sl:SetPoint("TOPLEFT", 0, y - 8)
        Loc(function() sl:SetText(Caps(T("arrowScale"))) end)
        local sv = FS(pg, 11, COL.white, FONT, "CENTER"); sv:SetWidth(60); sv:SetPoint("TOPLEFT", 216, y - 8)
        local function setS(d) DB.arrowScale = math.max(0.6, math.min(1.6, (DB.arrowScale or 1) + d)); RefreshOptions() end
        local m1 = FlatButton(pg, 28, 24, function() setS(-0.1) end); m1:SetPoint("TOPLEFT", 180, y - 2); m1:SetLabel("-")
        local p1 = FlatButton(pg, 28, 24, function() setS(0.1) end); p1:SetPoint("TOPLEFT", 284, y - 2); p1:SetLabel("+")
        local rs = FlatButton(pg, 200, 24, function() if ns.Arrow then ns.Arrow.Reset() end end)
        rs:SetPoint("TOPLEFT", 330, y - 2)
        Loc(function() rs:SetLabel(Caps(T("arrowReset"))) end)
        if rs.fs.SetFont then rs.fs:SetFont(FONT, 9, "") end
        optRows[#optRows + 1] = function() sv:SetText(math.floor((DB.arrowScale or 1) * 100 + 0.5) .. " %") end
        y = y - 40
        -- TRAJETS ET VOLS
        sec("secTrips")
        row(CheckRow(pg, CW, "useFlights", function() return DB.useFlights ~= false end,
            function(v) DB.useFlights = v; E.ResetWP(); Refresh(true) end))
        row(CheckRow(pg, CW, "hearthTips", function() return DB.hearthTips ~= false end,
            function(v) DB.hearthTips = v; Refresh(true) end))
        local BW2 = math.floor((CW - 12) / 2)
        local rc = FlatButton(pg, BW2, 28, function() SlashCmdList.WARPATH("now") end)
        rc:SetPoint("TOPLEFT", 0, y - 4)
        Loc(function() rc:SetLabel(Caps(T("recalc"))) end)
        local un = FlatButton(pg, BW2, 28, function() SlashCmdList.WARPATH("unskip all") end)
        un:SetPoint("TOPLEFT", BW2 + 12, y - 4)
        Loc(function() un:SetLabel(Caps(T("unignore"))) end)
        if un.fs.SetFont then un.fs:SetFont(FONT, 9, ""); rc.fs:SetFont(FONT, 9, "") end
        y = y - 48
        -- CIBLAGE
        sec("secTargeting")
        row(CheckRow(pg, CW, "targets", function() return DB.targets ~= false end, function(v) DB.targets = v; if ns.Targets then ns.Targets.Refresh() end end))
        local legend = FS(pg, 11, COL.gold, FONT, "LEFT"); legend:SetWidth(CW - 22)
        legend:SetPoint("TOPLEFT", 22, y)
        Loc(function()
            local function ico(n, r, g, b) return string.format("|TInterface\\AddOns\\OghoulesWarpath\\Media\\%s:12:12:0:0:32:32:0:32:0:32:%d:%d:%d|t", n, r, g, b) end
            legend:SetText(T("tgtLegend", ico("IcoAccept", 214, 184, 102), ico("IcoTurnin", 156, 199, 168),
                ico("IcoDo", 205, 187, 142), "|TInterface\\Minimap\\Tracking\\FlightMaster:12|t"))
        end)
    end

    -- 4. Affichage
    do
        -- v1.41 (audit, point 8) : trois sections : Fenetre · Messages · Extras (venus d'Automatisation)
        local pg = pages[6]
        local y = 0
        local function sec(key) local h = SmallHeader(pg, key); h:SetPoint("TOPLEFT", 0, y); y = y - 18 end
        local function row(r) r:SetPoint("TOPLEFT", 0, y); y = y - ROW_H end
        local function flag(key, field, def)
            return CheckRow(pg, CW, key, function() if def then return DB[field] ~= false end return DB[field] and true or false end,
                function(v) DB[field] = v; if field == "trainer" and not v then DB.trainDue = nil end; Refresh(true) end)
        end
        -- FENETRE
        sec("secWindow")
        row(CheckRow(pg, CW, "showWindow", function() return DB.shown ~= false end, function(v) E.ShowGuide(v) end))
        row(CheckRow(pg, CW, "lock", function() return DB.locked end, function(v) DB.locked = v end))
        row(CheckRow(pg, CW, "mmButton", function() return not DB.mmHide end,
            function(v) DB.mmHide = not v; if mm then mm:SetShown(v) end end))
        row(flag("miniOpt", "mini", false))
        row(flag("compact", "compact", false))
        y = y - 6
        -- taille de la fenetre : -  100 %  +
        local sl = FS(pg, 9, COL.gold, FONT, "LEFT"); sl:SetPoint("TOPLEFT", 0, y - 9)
        Loc(function() sl:SetText(Caps(T("scaleLbl"))) end)
        local val = FS(pg, 12, COL.white, FONT, "CENTER"); val:SetWidth(70); val:SetPoint("TOPLEFT", 190, y - 7)
        local function SetScale(v)
            v = math.max(0.6, math.min(1.5, math.floor(v * 20 + 0.5) / 20))
            DB.scale = v
            local f = E.Frame(); if f then f:SetScale(v); local mf = rawget(f, "mini"); if mf then mf:SetScale(v) end end
            val:SetText(math.floor(v * 100 + 0.5) .. " %")
        end
        local minus = FlatButton(pg, 28, 26, function() SetScale((DB.scale or 1) - 0.05) end); minus:SetPoint("TOPLEFT", 150, y); minus:SetLabel("-")
        local plus = FlatButton(pg, 28, 26, function() SetScale((DB.scale or 1) + 0.05) end); plus:SetPoint("TOPLEFT", 272, y); plus:SetLabel("+")
        optRows[#optRows + 1] = function() val:SetText(math.floor((DB.scale or 1) * 100 + 0.5) .. " %") end
        y = y - 46
        local rp = FlatButton(pg, 300, 28, function()
            DB.wpos = nil
            local f = E.Frame()
            if f then
                f:ClearAllPoints()
                if Minimap then f:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 12, -36)
                else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -240) end
            end
        end)
        rp:SetPoint("TOPLEFT", 0, y)
        Loc(function() rp:SetLabel(Caps(T("resetPos"))) end)
        if rp.fs.SetFont then rp.fs:SetFont(FONT, 9, "") end
        y = y - 44
        -- MESSAGES : chat (tous / importants / aucun ; erreurs et commandes toujours), conseils, rappel d'entraineur
        sec("secMessages")
        local cl = FS(pg, 12, COL.white, FONT, "LEFT"); cl:SetPoint("TOPLEFT", 22, y - 7)
        Loc(function() cl:SetText(T("chatLbl")) end)
        local LV = { "all", "important", "none" }
        local cb = FlatButton(pg, 170, 24, function()
            local cur = DB.chatLevel or "all"
            local k = 1; for i, v in ipairs(LV) do if v == cur then k = i end end
            DB.chatLevel = LV[k % #LV + 1]
            RefreshOptions()
        end)
        cb:SetPoint("TOPLEFT", 200, y)
        optRows[#optRows + 1] = function() cb:SetLabel(T("chat_" .. (DB.chatLevel or "all"))) end
        cb:HookScript("OnEnter", function(self) local t = E.Tip(); t:SetOwner(self, "ANCHOR_RIGHT"); t:AddLine(T("chatTip"), 1, 1, 1, true); t:Show() end)
        cb:HookScript("OnLeave", function() E.Tip():Hide() end)
        y = y - 30
        row(flag("tipsOpt", "tips", true))
        row(flag("trainerOpt", "trainer", true))
        y = y - 10
        -- EXTRAS : Trophees de guerre, Chronique (venus de l'onglet Automatisation ; la ligne XP/h a disparu avec le pied)
        sec("hdrExtras")
        row(CheckRow(pg, CW, "pvpShow", function() return not (WarpathDropDB and WarpathDropDB._pvpShow == false) end,
            function(v) if WarpathDropDB then WarpathDropDB._pvpShow = v end; if _G.WarpathPvPRefresh then pcall(_G.WarpathPvPRefresh, true) end end))
        row(CheckRow(pg, CW, "pvpShot", function() return DB.pvpShot and true or false end, function(v) DB.pvpShot = v end))
        row(CheckRow(pg, CW, "chronBanner", function() return DB.chronBanner ~= false end, function(v) DB.chronBanner = v end))
        local cv = FlatButton(pg, 200, 24, function() E.ChronShow() end)
        cv:SetPoint("TOPLEFT", 0, y - 4)
        Loc(function() cv:SetLabel(K.Upper(T("chOpen"))) end)
    end

    -- Automatisation
    do
        local pg = pages[7]
        local h = SmallHeader(pg, "tabAuto"); h:SetPoint("TOPLEFT", 0, 0)
        local y = -18
        for _, o in ipairs({ { "autoQuest", "autoQuest" }, { "autoFly", "autoFly" }, { "itemBtn", "itemBtn" }, { "nearOpt", "near" }, { "smartArrowOpt", "smartArrow" }, { "trailOpt", "trailAsk" } }) do
            local field = o[2]
            local r = CheckRow(pg, CW, o[1], function() return DB[field] ~= false end, function(v) DB[field] = v; Refresh(true) end)
            r:SetPoint("TOPLEFT", 0, y); y = y - ROW_H
        end
        local sh = CheckRow(pg, CW, "shareOpt", function() return WarpathDropDB and WarpathDropDB._share ~= false end,
            function(v) if WarpathDropDB then WarpathDropDB._share = v end end)
        sh:SetPoint("TOPLEFT", 0, y); y = y - ROW_H - 10
        local note = FS(pg, 10, COL.soft, FONT, "LEFT"); note:SetWidth(CW); note:SetPoint("TOPLEFT", 0, y)
        Loc(function() note:SetText(T("autoNote")) end)
        -- (les extras sont passes dans l'onglet Affichage en v1.41)
    end

    opt:SetScript("OnShow", function()
        wipe(statusCache)
        for _, fn in ipairs(showHooks) do fn() end
        RefreshOptions()
    end)
    ShowTab(DB.optTab or 1)
    showTabFn = ShowTab
end

ui.RefreshOptions = RefreshOptions

local function OpenOptionsTab(k)
    CreateOptions()
    opt:Show()
    if showTabFn then showTabFn(k) end
end

local function ToggleOptions()
    CreateOptions()
    opt:SetShown(not opt:IsShown())
end

------------------------------------------------------------------
-- Bouton de minimap (losange)
------------------------------------------------------------------
local function CreateMinimapButton()
    if mm or not Minimap then return end
    mm = CreateFrame("Button", "WarpathMinimapButton", Minimap)
    mm:SetSize(28, 28)
    mm:SetFrameStrata("MEDIUM")
    mm:SetFrameLevel(8)
    mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mm:RegisterForDrag("LeftButton")
    local icon = mm:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetAllPoints()
    local hl = mm:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(ICON)
    hl:SetAllPoints()
    if hl.SetBlendMode then hl:SetBlendMode("ADD") end
    if hl.SetAlpha then hl:SetAlpha(0.35) end
    mm:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            E.ShowGuide(DB.shown == false); RefreshOptions()
        else
            ToggleOptions()
        end
    end)
    mm:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local sc = Minimap:GetEffectiveScale()
            local atan2 = math.atan2 or atan2
            DB.mmAngle = math.deg(atan2(py / sc - my, px / sc - mx))
            MinimapPos()
        end)
    end)
    mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mm:SetScript("OnEnter", function(self)
        E.Tip():SetOwner(self, "ANCHOR_LEFT")
        E.Tip():AddLine(E.WarpathName(), 0.93, 0.90, 0.85)
        local G, steps = E.Guide(), E.Steps()
        if G and steps then
            E.Tip():AddLine(T("mmStep", Title(G), math.min(E.Current(), #steps), #steps), 0.8, 0.73, 0.56)
        end
        E.Tip():AddLine(T("mmLeft"), 0.66, 0.60, 0.48)
        E.Tip():AddLine(T("mmRight"), 0.66, 0.60, 0.48)
        E.Tip():AddLine(T("mmDrag"), 0.66, 0.60, 0.48)
        E.Tip():Show()
    end)
    mm:SetScript("OnLeave", function() E.Tip():Hide() end)
    MinimapPos()
    mm:SetShown(not DB.mmHide)
end

-- Entree dans le menu Options > AddOns du jeu (ouvre notre fenetre)
local function RegisterBlizzardOptions()
    local panel = CreateFrame("Frame")
    panel.name = "Oghoule's Warpath"
    local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16)
    t:SetText("|T" .. ICON .. ":24|t  " .. E.WarpathName())
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(200, 26)
    b:SetPoint("TOPLEFT", 16, -56)
    b:SetText(T("openOptions"))
    b:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel.Hide then pcall(SettingsPanel.Hide, SettingsPanel) end
        if InterfaceOptionsFrame and InterfaceOptionsFrame.Hide then pcall(InterfaceOptionsFrame.Hide, InterfaceOptionsFrame) end
        CreateOptions(); opt:Show()
    end)
    pcall(function()
        if Settings and Settings.RegisterCanvasLayoutCategory then
            local cat = Settings.RegisterCanvasLayoutCategory(panel, "Oghoule's Warpath")
            Settings.RegisterAddOnCategory(cat)
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(panel)
        end
    end)
end

ui.ToggleOptions = ToggleOptions
ui.OpenOptionsTab = OpenOptionsTab
ui.SetLang = SetLang
ui.CreateMinimapButton = function() CreateMinimapButton(); ui.mm = mm end
ui.RegisterBlizzardOptions = RegisterBlizzardOptions
