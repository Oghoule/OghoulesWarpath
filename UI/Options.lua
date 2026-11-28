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
        local glow = self.glow and self.glow:IsShown()
        if not self.tipKey and not glow and not self.offRoute then return end
        E.Tip():SetOwner(self, "ANCHOR_RIGHT")
        if self.offRoute then E.Tip():AddLine(T("stOffRoute")); E.Tip():AddLine(T("stOffRouteTip"), 1, 1, 1, true) end
        if self.tipKey then E.Tip():AddLine(T("stLow")); E.Tip():AddLine(T(self.tipKey), 1, 1, 1, true) end
        if glow then E.Tip():AddLine(T("atLevel"), 0.88, 0.74, 0.43) end
        E.Tip():Show()
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

-- v1.45 : contour dore « a ton niveau » sur un bouton de liste, avec l'infobulle (ajoutee au survol existant)
local function GlowRow(b)
    local g = K.GoldFrame(b)
    if b.HookScript then
        b:HookScript("OnEnter", function(self)
            if not g:IsShown() then return end
            E.Tip():SetOwner(self, "ANCHOR_RIGHT"); E.Tip():AddLine(T("atLevel"), 0.88, 0.74, 0.43); E.Tip():Show()
        end)
        b:HookScript("OnLeave", function() E.Tip():Hide() end)
    end
    return g
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

-- v1.46 : une seule ligne de reglage de taille, la meme pour la fenetre et la fleche :
-- libelle · - · valeur · + · « 100 % » (remet a 100 %). Pas de 5 %, de 60 a 160 %.
local SCALE_MIN, SCALE_MAX = 0.6, 1.6
local function ScaleRow(pg, y, lblKey, get, set)
    local sl = FS(pg, 12, COL.white, FONT, "LEFT"); sl:SetPoint("TOPLEFT", 22, y - 7)
    Loc(function() sl:SetText(T(lblKey)) end)
    local val = FS(pg, 12, COL.white, FONT, "CENTER"); val:SetWidth(64); val:SetPoint("TOPLEFT", 232, y - 7)
    local function show() val:SetText(math.floor((get() or 1) * 100 + 0.5) .. " %") end
    local function apply(v)
        v = math.max(SCALE_MIN, math.min(SCALE_MAX, math.floor(v * 20 + 0.5) / 20))
        set(v); show()
    end
    local m = FlatButton(pg, 28, 24, function() apply((get() or 1) - 0.05) end); m:SetPoint("TOPLEFT", 200, y - 1); m:SetLabel("-")
    local p = FlatButton(pg, 28, 24, function() apply((get() or 1) + 0.05) end); p:SetPoint("TOPLEFT", 300, y - 1); p:SetLabel("+")
    local r = FlatButton(pg, 64, 24, function() apply(1) end); r:SetPoint("TOPLEFT", 340, y - 1); r:SetLabel("100 %")
    if r.fs and r.fs.SetFont then r.fs:SetFont(FONT, 10, "") end
    optRows[#optRows + 1] = show
    return y - 30
end

-- v1.52 (audit des options) : haut de l'onglet Parcours (resume, deux cartes de parcours, style de jeu).
-- A part de CreateOptions, qui depassait la limite de 200 variables locales du Lua 5.1 de WoW.
local function BuildRouteStyle(pg)
    -- v1.52 (audit des options) : onglet Parcours = resume, parcours (deux cartes), style de jeu, puis la zone
    local sum = FS(pg, 12, COL.white, FONT, "LEFT"); sum:SetWidth(CW); sum:SetPoint("TOPLEFT", 0, 0)
    optRows[#optRows + 1] = function()
        local wb = ns.Mod.Core.Parcours() == "warband"
        local g = DB.guide
        sum:SetText(T("optSum", "|cffd6b866" .. Caps(T(wb and "routeWarband" or "routeScout")) .. "|r",
            "|cffd6b866" .. ((g and Guides[g]) and Caps(ZoneName(g)) or "—") .. "|r"))
    end
    -- PARCOURS : un clic sur une carte change de parcours (rien n'est perdu)
    local ph = SmallHeader(pg, "secParcours"); ph:SetPoint("TOPLEFT", 0, -26)
    local CWH = math.floor((CW - 12) / 2)
    for k, r in ipairs({ "warband", "scout" }) do
        local c = CreateFrame("Button", nil, pg); c:SetSize(CWH, 40)
        c:SetPoint("TOPLEFT", (k - 1) * (CWH + 12), -44)
        local cb = Tex(c, { 0.16, 0.06, 0.05 }, 1, "BACKGROUND"); cb:SetAllPoints()
        -- v1.52 (demande de l'auteur) : images de l'ecran de choix (Media/Choix*, a lui, hors Git), recadrees sur la
        -- bande des yeux, placee a droite ; version « Fx » en fondu au survol ; fondu sombre a gauche sous le texte.
        -- Seulement avec /warpath art (WarpathDropDB._artPerso) ; sinon la carte reste unie.
        if WarpathDropDB and WarpathDropDB._artPerso then
            local BAND = { warband = { 0.242, 0.633, 0.156, 0.186 }, scout = { 0.047, 0.750, 0.200, 0.254 } }
            local base, b = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Choix" .. (r == "warband" and "Warband" or "Scout"), BAND[r]
            c.art = c:CreateTexture(nil, "BACKGROUND", nil, 1); c.art:SetAllPoints(); c.art:SetTexture(base)
            c.fx = c:CreateTexture(nil, "BACKGROUND", nil, 2); c.fx:SetAllPoints(); c.fx:SetTexture(base .. "Fx"); c.fx:SetAlpha(0)
            for _, t in ipairs({ c.art, c.fx }) do t:SetTexCoord(b[1], b[2], b[3], b[4]) end
            local sh = c:CreateTexture(nil, "BACKGROUND", nil, 3)
            sh:SetPoint("TOPLEFT"); sh:SetPoint("BOTTOMLEFT"); sh:SetWidth(math.floor(CWH * 0.62))
            sh:SetColorTexture(1, 1, 1, 1)
            local d0, d1 = { 0.06, 0.03, 0.02, 0.92 }, { 0.06, 0.03, 0.02, 0 }
            if CreateColor and sh.SetGradient then
                pcall(sh.SetGradient, sh, "HORIZONTAL", CreateColor(d0[1], d0[2], d0[3], d0[4]), CreateColor(d1[1], d1[2], d1[3], d1[4]))
            elseif sh.SetGradientAlpha then
                sh:SetGradientAlpha("HORIZONTAL", d0[1], d0[2], d0[3], d0[4], d1[1], d1[2], d1[3], d1[4])
            end
            c.fxA, c.want = 0, 0
            c:SetScript("OnUpdate", function(self, el)
                if self.fxA == self.want then return end
                local step = (el or 0.016) * 4
                self.fxA = (self.want > self.fxA) and math.min(self.want, self.fxA + step) or math.max(self.want, self.fxA - step)
                self.fx:SetAlpha(self.fxA)
            end)
        end
        K.Border(c, COL.line, 0.9)
        local chl = Tex(c, COL.accent, 0.08, "HIGHLIGHT"); chl:SetAllPoints()
        c.glow = K.GoldFrame(c)
        c.gem = Diamond(c, 7, COL.red); c.gem:SetPoint("TOPLEFT", 10, -10)
        c.name = FS(c, 11, COL.accent, FONT, "LEFT"); c.name:SetPoint("TOPLEFT", 24, -6)
        c.desc = FS(c, 10, COL.soft, FONT, "LEFT"); c.desc:SetPoint("TOPLEFT", 24, -22); c.desc:SetPoint("RIGHT", -8, 0)
        if c.desc.SetWordWrap then c.desc:SetWordWrap(false) end
        Loc(function()
            c.name:SetText(Caps(T(r == "warband" and "routeWarband" or "routeScout")))
            c.desc:SetText(T(r == "warband" and "routeWarbandShort" or "routeScoutShort"))
        end)
        c:SetScript("OnClick", function()
            local Ch = ns.Mod.Choice
            if ns.Mod.Core.Parcours() ~= r and Ch and Ch.SetRoute then Ch.SetRoute(r) end
            RefreshOptions()
        end)
        c:SetScript("OnEnter", function(self)
            self.want = 1
            E.Tip():SetOwner(self, "ANCHOR_RIGHT"); E.Tip():AddLine(T(r == "warband" and "routeWarband" or "routeScout"))
            E.Tip():AddLine(T(r == "warband" and "routeWarbandTip" or "routeScoutTip"), 1, 1, 1, true); E.Tip():Show()
        end)
        c:SetScript("OnLeave", function(self) self.want = 0; E.Tip():Hide() end)
        optRows[#optRows + 1] = function()
            local on = ns.Mod.Core.Parcours() == r
            c.glow:SetOn(on); c.gem:SetShown(on)
            local col = on and COL.accent or COL.soft
            if c.name.SetTextColor then c.name:SetTextColor(col[1], col[2], col[3]) end
        end
    end
    -- STYLE DE JEU (venu de l'onglet Style) : prereglages, puis trois choix et deux cases
    local sh2 = SmallHeader(pg, "tabStyle"); sh2:SetPoint("TOPLEFT", 0, -96)
    local sy = -114
    local pl = FS(pg, 10, COL.gold, FONT, "LEFT"); pl:SetPoint("TOPLEFT", 0, sy - 8)
    Loc(function() pl:SetText(Caps(T("presets"))) end)
    local plh = CreateFrame("Frame", nil, pg); plh:SetSize(130, 24); plh:SetPoint("TOPLEFT", 0, sy)
    if plh.EnableMouse then plh:EnableMouse(true) end
    plh:SetScript("OnEnter", function(self) E.Tip():SetOwner(self, "ANCHOR_RIGHT"); E.Tip():AddLine(T("stNote"), 1, 1, 1, true); E.Tip():Show() end)
    plh:SetScript("OnLeave", function() E.Tip():Hide() end)
    local PW = math.floor((CW - 140) / 4) - 6
    for k, p in ipairs({ "solo", "group", "calm", "safe" }) do
        local b = FlatButton(pg, PW, 24, function() E.ApplyPreset(p); RefreshOptions() end)
        b:SetPoint("TOPLEFT", 140 + (k - 1) * (PW + 6), sy)
        Loc(function() b:SetLabel(Caps(T("preset_" .. p))) end)
        if b.fs.SetFont then b.fs:SetFont(FONT, 9, "") end
    end
    sy = sy - 30
    local CHW = math.floor((CW - 140) / 3) - 4
    for _, gdef in ipairs({ { "stElite", "elite", { "always", "group", "never" } }, { "stXp", "xpMode", { "farm", "dungeon", "both" } } }) do   -- (v1.52 : « Priorite » retiree)
        local labelKey, field = gdef[1], gdef[2]
        local lab = FS(pg, 10, COL.gold, FONT, "LEFT"); lab:SetPoint("TOPLEFT", 0, sy - 8); lab:SetWidth(136)
        Loc(function() lab:SetText(Caps(T(labelKey))) end)
        for k, ch in ipairs(gdef[3]) do
            local r = ChoiceRow(pg, CHW, function() E.StyleGet()[field] = ch; RefreshOptions(); E.StyleChanged() end)
            r:SetPoint("TOPLEFT", 140 + (k - 1) * (CHW + 4), sy); r.top:Hide()
            Loc(function() r.label:SetText(T("st_" .. field .. "_" .. ch)) end)
            optRows[#optRows + 1] = function() r:SetChecked(E.StyleGet()[field] == ch) end
        end
        sy = sy - 28
    end
    local es = CheckRow(pg, CWH, "stEscort", function() return E.StyleGet().noEscort end,
        function(v) E.StyleGet().noEscort = v and true or nil; E.StyleChanged() end)
    es:SetPoint("TOPLEFT", 0, sy)
    local pr = CheckRow(pg, CWH, "stPrudent", function() return E.StyleGet().prudent end,
        function(v) E.StyleGet().prudent = v and true or nil; E.StyleChanged() end)
    pr:SetPoint("TOPLEFT", CWH + 12, sy)
end

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
    -- v1.52 (audit des options) : 7 onglets en 2 groupes. TON AVENTURE (quoi faire) : Parcours, Donjons,
    -- Quetes a part ; REGLAGES (comment l'addon t'aide) : Guidage, Propositions, Fenetre, Extras.
    local TABS = { "tabParcours", "tabDungeons", "tabQuests", "tabGuide", "tabPropose", "tabWindow", "tabExtras" }
    local ORDER = { 1, 2, 3, 4, 5, 6, 7 }
    local GROUP_AT = { [1] = "grpAdventure", [4] = "grpSettings" }   -- titre de groupe avant cette position
    local navLine = Tex(opt, COL.faint); navLine:SetWidth(1)
    navLine:SetPoint("TOPLEFT", NAVW + 10, -58); navLine:SetPoint("BOTTOMLEFT", NAVW + 10, 34)
    local ny = -50
    for pos, k in ipairs(ORDER) do
        local key = TABS[k]
        if GROUP_AT[pos] then
            if pos > 1 then ny = ny - 12 end
            local gh = FS(opt, 9, COL.dim, FONT, "LEFT"); gh:SetPoint("TOPLEFT", 28, ny)
            local gk = GROUP_AT[pos]
            Loc(function() gh:SetText(Caps(T(gk))) end)
            ny = ny - 16
        end
        local tb = CreateFrame("Button", nil, opt)
        tb:SetSize(NAVW - 20, 32)
        tb:SetPoint("TOPLEFT", 20, ny); ny = ny - 36
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

    -- 1. Campagne : une seule liste de zones sur deux colonnes, puis la langue
    -- v1.45 (demande de l'auteur) : colonne « zone suivante » retiree (doublon de la question de fin de zone ;
    -- DB.nextGuide sert encore au bouton « Rester » de cette question). Zones finies et trop basses masquees
    -- par defaut (case en bas, DB.zonesAll) : la liste tient sur une page au lieu de trois.
    do
        local pg = pages[1]
        local colW = math.floor((CW - 24) / 2)
        BuildRouteStyle(pg)   -- resume, parcours, style de jeu (fonction a part : limite de 200 locales du Lua 5.1)
        -- ZONE (l'ancien onglet Campagne, en plus court : 6 lignes par colonne)
        local h1 = SmallHeader(pg, "chapters"); h1:SetPoint("TOPLEFT", 0, -234)
        local y = -250
        local auto = ChoiceRow(pg, CW, function()
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
            auto.status:SetText("")   -- v1.52 : le nom de la zone est deja dans le resume en haut
        end
        y = y - ROW_H
        local ROWS = 7
        local PER = ROWS * 2
        local all = {}
        for _, key in ipairs(MAIN_ORDER) do if Guides[key] then all[#all + 1] = key end end
        local list, hidden, page, npages = {}, 0, 1, 1
        local function hide(key)
            local st = GuideState(key)
            -- v1.52 (demande de l'auteur) : aussi les zones qui commencent plus de 10 niveaux au-dessus du tien
            local lo = GuideRange(key)
            local me = UnitLevel and UnitLevel("player") or 1
            return (st == "done" or st == "low" or (lo or 1) > me + 10) and key ~= DB.guide
        end
        local function build()
            list, hidden = {}, 0
            for _, key in ipairs(all) do
                if DB.zonesAll or not hide(key) then list[#list + 1] = key else hidden = hidden + 1 end
            end
            npages = math.max(1, math.ceil(#list / PER))
            if page > npages then page = npages end
        end
        local slots = {}
        for k = 1, PER do
            local col, row = math.floor((k - 1) / ROWS), (k - 1) % ROWS
            local b = ChoiceRow(pg, colW, function(self)
                if not self.key then return end
                DB.manual = true
                SetGuide(self.key)
                RefreshOptions()
            end)
            b:SetPoint("TOPLEFT", col * (colW + 24), y - row * ROW_H)
            b.glow = K.GoldFrame(b)   -- zone a ton niveau
            slots[k] = b
        end
        y = y - ROWS * ROW_H - 6
        -- case « afficher aussi les zones finies et trop basses » (a gauche), pages (a droite, si besoin)
        local showAll = CheckRow(pg, colW + 60, "zonesAll", function() return DB.zonesAll and true or false end,
            function(v) DB.zonesAll = v or nil; RefreshOptions() end)
        showAll:SetPoint("TOPLEFT", 0, y)
        local pageLbl = FS(pg, 9, COL.gold, FONT, "CENTER"); pageLbl:SetWidth(90)
        pageLbl:SetPoint("TOPRIGHT", pg, "TOPRIGHT", -40, y - 7)
        local prevB = FlatButton(pg, 28, 22, function() page = math.max(1, page - 1); RefreshOptions() end)
        prevB:SetPoint("TOPRIGHT", pageLbl, "TOPLEFT", -6, 5); prevB:SetLabel("<")
        local nextB = FlatButton(pg, 28, 22, function() page = math.min(npages, page + 1); RefreshOptions() end)
        nextB:SetPoint("TOPLEFT", pageLbl, "TOPRIGHT", 6, 5); nextB:SetLabel(">")
        showHooks[#showHooks + 1] = function()
            build(); page = 1
            for i, key in ipairs(list) do if key == DB.guide then page = math.ceil(i / PER) end end
        end
        optRows[#optRows + 1] = function()
            build()
            local paged = npages > 1
            pageLbl:SetShown(paged); prevB:SetShown(paged); nextB:SetShown(paged)
            pageLbl:SetText(Caps(T("pageLbl", page, npages)))
            showAll.label:SetText(T("zonesAll", hidden))
            showAll:SetShown(DB.zonesAll or hidden > 0)
            local me = UnitLevel and UnitLevel("player") or 0
            for k = 1, PER do
                local key = list[(page - 1) * PER + k]
                local b = slots[k]
                b.key = key
                b:SetShown(key ~= nil)
                b.glow:SetOn(false)
                if key then
                    local lo, hi = GuideRange(key)
                    local st = GuideState(key)
                    b.glow:SetOn(false)   -- v1.52 (demande de l'auteur) : plus de contour dore « a ton niveau » dans la liste
                    b:SetChecked(DB.guide == key)   -- v1.52 : la zone en cours (auto ou choisie) = losange rouge
                    b.label:SetText(ZoneName(key))
                    b.status:SetText((st == "done" and ("|cff9cc7a8" .. Caps(T("stDone")) .. "|r"))
                        or (st == "low" and ("|cff8c7f62" .. Caps(T("stLow")) .. "|r")) or (lo .. " - " .. hi))
                    b.tipKey = (st == "low") and "stLowTip" or nil
                    -- v1.52 : zone sautee par la Bande de guerre : grisee, toujours choisissable
                    local C = ns.Mod.Core
                    local skip = C.D and C.D.WARBAND_SKIP
                    b.offRoute = (C.Parcours() == "warband" and skip and skip[key]) and true or nil
                    if b.offRoute then
                        b.glow:SetOn(false)
                        if not b.checked and b.label.SetTextColor then b.label:SetTextColor(COL.line[1], COL.line[2], COL.line[3]) end
                        if st ~= "done" then b.status:SetText("|cff8c7f62" .. Caps(T("stOffRoute")) .. "|r") end
                    end
                end
            end
        end
        -- (v1.52, audit des options : la langue est passee dans Fenetre)
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
                -- v1.46 : un clic ouvre la fiche du donjon (ses quetes) ; « Prendre les quetes » y lance le guide
                local b = FlatButton(pg, BW, 23, function()
                    if not (E.DungeonSheetOpen and E.DungeonSheetOpen(d.key)) then StartDungeon(d.key) end
                    RefreshOptions()
                end)
                b:SetPoint("TOPLEFT", col * (BW + 8), y - row * 26)
                b.fs:ClearAllPoints(); b.fs:SetPoint("LEFT", 10, 0)
                b.fs:SetText(E.DungeonName(d))
                if b.fs.SetFont then b.fs:SetFont(FONT, 10, "") end
                local lv = FS(b, 9, COL.gold, FONT, "RIGHT"); lv:SetPoint("RIGHT", -10, 0)
                -- v1.42 : le nom s'arrete avant les niveaux (coupe en « ... » si trop long)
                -- v1.46 : compteurs « ! 3 » (a prendre maintenant, dore) et « +2 » (niveau trop bas, rouge)
                -- « ! 3 » dans un petit cadre dore ; « +2 » dans un cadre rouge a sa gauche ; le nom s'arrete avant
                local bx = CreateFrame("Frame", nil, b); bx:SetSize(24, 15); bx:SetPoint("RIGHT", lv, "LEFT", -6, 0)
                bx.edge = K.Border(bx, COL.accent, 0.8)
                bx.fs = FS(bx, 9, COL.accent, FONT, "CENTER"); bx.fs:SetPoint("CENTER", 0, 0)
                local RED = { 0.76, 0.29, 0.24 }
                local red = CreateFrame("Frame", nil, b); red:SetSize(24, 15)
                K.Border(red, RED, 0.8)
                red.fs = FS(red, 9, RED, FONT, "CENTER"); red.fs:SetPoint("CENTER", 0, 0)
                function red:SetText(s) self.fs:SetText(s); self:SetWidth(math.max(20, (self.fs:GetStringWidth() or 12) + 10)) end
                b.fs:SetJustifyH("LEFT")
                local function place(hasB, hasR)
                    bx:SetShown(hasB); red:SetShown(hasR)
                    red:ClearAllPoints(); red:SetPoint("RIGHT", hasB and bx or lv, "LEFT", hasB and -4 or -6, 0)
                    b.fs:ClearAllPoints(); b.fs:SetPoint("LEFT", 10, 0)
                    b.fs:SetPoint("RIGHT", hasR and red or (hasB and bx) or lv, "LEFT", -6, 0)
                end
                if b.fs.SetWordWrap then b.fs:SetWordWrap(false) end
                b.glow = K.GoldFrame(b)   -- v1.45 : donjon a ton niveau, avec des quetes a faire
                optRows[#optRows + 1] = function()
                    local me = UnitLevel and UnitLevel("player") or 0
                    local inRange = me >= d.min and me <= d.max
                    local okL, left = pcall(E.DungeonLeft, d.key)
                    b.glow:SetOn(inRange and okL and (left or 0) > 0)
                    local ideal = E.DungeonIdeal(d.key)
                    lv:SetText((inRange and "|cffcdbb8e" or "") .. d.min .. "-" .. d.max .. (inRange and "|r" or "")
                        .. (ideal and ("  |cff8c7f62·|r " .. ((me >= ideal and inRange) and "|cffcdbb8e" or "") .. ideal .. ((me >= ideal and inRange) and "|r" or "")) or ""))
                    local okB, take, later, lvlL = pcall(E.DungeonBadge or function() return 0, 0 end, d.key)
                    if not okB then take, later = 0, 0 end
                    b.take, b.later, b.lvlL = take or 0, later or 0, lvlL
                    local hasB, hasR = (take or 0) > 0, (later or 0) > 0
                    if hasB then
                        local bc = (me >= d.min) and COL.accent or COL.dim
                        bx.fs:SetText("! " .. take)
                        if bx.fs.SetTextColor then bx.fs:SetTextColor(bc[1], bc[2], bc[3]) end
                        for _, t in ipairs(bx.edge) do if t.SetColorTexture then t:SetColorTexture(bc[1], bc[2], bc[3], 0.8) end end
                        bx:SetWidth(math.max(20, (bx.fs:GetStringWidth() or 12) + 10))
                    end
                    red:SetText(hasR and ("+" .. later) or "")
                    place(hasB, hasR)
                    b.fs:SetText(E.DungeonName(d))   -- suit la langue choisie
                    local active = (DB.guide == d.key)
                    local c = active and COL.accent or COL.white
                    if b.fs.SetTextColor then b.fs:SetTextColor(c[1], c[2], c[3]) end
                end
                b:SetScript("OnEnter", function(self)
                    E.Tip():SetOwner(self, "ANCHOR_RIGHT")
                    E.Tip():AddLine(E.DungeonName(d))
                    E.Tip():AddLine(T("dTip", d.min, d.max), 1, 1, 1, true)
                    local ideal = E.DungeonIdeal(d.key)
                    if ideal then E.Tip():AddLine(T("dIdeal", ideal), 0.84, 0.72, 0.4, true) end
                    if b.glow:IsShown() then E.Tip():AddLine(T("atLevel"), 0.88, 0.74, 0.43) end
                    if (b.take or 0) > 0 then E.Tip():AddLine(T("dsBadgeTip", b.take), 0.84, 0.72, 0.4) end
                    if (b.later or 0) > 0 and b.lvlL then E.Tip():AddLine(T("dsLaterTip", b.later, b.lvlL), 0.76, 0.29, 0.24) end
                    E.Tip():AddLine(T("dsClickTip"), 0.55, 0.5, 0.38)
                    E.Tip():Show()
                end)
                b:SetScript("OnLeave", function() E.Tip():Hide() end)
            end
        end
        y = y - math.ceil(n / 2) * 26
        y = y - 6
        -- (v1.52, audit des options : « Me proposer les donjons » est dans Propositions)
        local stop = FlatButton(pg, 200, 28, function() StopDungeon(); RefreshOptions() end)
        stop:SetPoint("TOPLEFT", 0, y)
        Loc(function() stop:SetLabel(Caps(T("leaveDungeon"))) end)
    end

    -- 3. Quetes a part (v1.52, audit des options, demande de l'auteur) : quetes de classe, quetes speciales
    -- (Cozy Sleeping Bag...) et quetes de metier dans le meme onglet. Les metiers sont ceux que le perso a
    -- appris (lus dans le jeu) : plus de cases a cocher. Les trois listes se placent l'une sous l'autre.
    do
        local pg = pages[3]
        local function listRow(onClick)
            local b = FlatButton(pg, CW, 26, onClick)
            b.fs:ClearAllPoints(); b.fs:SetPoint("LEFT", 12, 0)
            if b.fs.SetFont then b.fs:SetFont(FONT, 11, "") end
            b.lv = FS(b, 9, COL.gold, FONT, "RIGHT"); b.lv:SetPoint("RIGHT", -12, 0)
            b.glow = GlowRow(b)   -- quete que tu peux faire maintenant
            return b
        end
        local hClass, hSp, hProf = SmallHeader(pg, "tabClass"), SmallHeader(pg, "specialHdr"), SmallHeader(pg, "tabProf")
        local cRows, sRows, pRows = {}, {}, {}
        for k = 1, 4 do cRows[k] = listRow(function(self) if self.q then E.AskClass(self.q) end end) end
        for k = 1, 2 do sRows[k] = listRow(function(self) if self.k then E.AskSpecial(self.k) end end) end
        for k = 1, 5 do pRows[k] = listRow(function(self) if self.q then E.AskProf(self.q) end end) end
        local cNone = FS(pg, 11, COL.soft, FONT, "LEFT"); cNone:SetWidth(CW)
        local mine = FS(pg, 11, COL.soft, FONT, "LEFT"); mine:SetWidth(CW)
        if mine.SetWordWrap then mine:SetWordWrap(true) end
        local pNone = FS(pg, 11, COL.soft, FONT, "LEFT"); pNone:SetWidth(CW)
        optRows[#optRows + 1] = function()
            local me = UnitLevel and UnitLevel("player") or 0
            local y = 0
            local function at(o, h) o:ClearAllPoints(); o:SetPoint("TOPLEFT", 0, y); y = y - h end
            -- QUETES DE CLASSE : celles qui restent a faire d'abord (4 au plus)
            at(hClass, 18)
            local all, list = E.ClassQuestList() or {}, {}
            for _, c in ipairs(all) do if not c.done then list[#list + 1] = c end end
            for _, c in ipairs(all) do if c.done then list[#list + 1] = c end end
            cNone:SetText(T("classNone")); cNone:SetShown(#list == 0)
            if #list == 0 then at(cNone, 22) end
            for k, b in ipairs(cRows) do
                local c = list[k]
                if c then
                    b.q = (not c.done) and c.q or nil
                    b.fs:SetText(c.label or c.name)
                    -- v1.47 : autre version d'une quete de classe deja faite (alt) : discrete, pas mise en avant
                    local col = c.done and COL.gold or ((me >= c.lvl and not c.alt) and COL.white or COL.soft)
                    if b.fs.SetTextColor then b.fs:SetTextColor(col[1], col[2], col[3]) end
                    -- v1.47 : chaine integree au guide (un clic rouvre la question, avec « Retirer du guide »)
                    local woven = (not c.done) and c.q and DB.woven and DB.woven[c.q]
                    b.lv:SetText(c.done and T("classDone") or woven and Caps(T("wovenTag")) or c.alt and T("classAlt") or (c.lvl2 > c.lvl and T("classLvls", c.lvl, c.lvl2) or T("classLvl", c.lvl)))
                    b.glow:SetOn(not c.done and not c.alt and me >= c.lvl)
                    at(b, 30); b:Show()
                else
                    b.q = nil; b.glow:SetOn(false); b:Hide()
                end
            end
            y = y - 10
            -- QUETES SPECIALES : un clic ouvre la proposition (« Faire maintenant »)
            local okS, sp = pcall(E.SpecialList)
            if not okS or type(sp) ~= "table" then sp = {} end
            hSp:SetShown(#sp > 0)
            if #sp > 0 then at(hSp, 18) end
            for k, b in ipairs(sRows) do
                local c = sp[k]
                if c then
                    b.k = (c.state ~= "done") and c.key or nil
                    b.fs:SetText(c.name)
                    local col = (c.state == "done") and COL.gold or ((me >= c.lvl) and COL.white or COL.soft)
                    if b.fs.SetTextColor then b.fs:SetTextColor(col[1], col[2], col[3]) end
                    b.lv:SetText(c.state == "done" and T("classDone") or (c.state == "doing" and T("spStateDoing", c.n, c.total)) or T("classLvl", c.lvl))
                    b.glow:SetOn(c.state ~= "done" and me >= c.lvl)
                    at(b, 30); b:Show()
                else
                    b.k = nil; b.glow:SetOn(false); b:Hide()
                end
            end
            if #sp > 0 then y = y - 10 end
            -- METIERS : ceux que tu as appris, puis leurs quetes (5 au plus)
            at(hProf, 18)
            local okD, det = pcall(E.ProfDetect)
            if not okD or type(det) ~= "table" then det = {} end
            local names = {}
            for _, id in ipairs(E.ProfOrder() or {}) do
                local r = det[id]
                if r then names[#names + 1] = E.ProfName(id) .. ((type(r) == "number" and r > 0) and (" (" .. r .. ")") or "") end
            end
            mine:SetText(#names > 0 and T("profMine", table.concat(names, ", ")) or T("profNoneLearned"))
            at(mine, math.max(20, ((mine.GetStringHeight and mine:GetStringHeight()) or 14) + 8))
            local plist, seen = {}, {}
            if #names > 0 then
                -- une meme quete existe en plusieurs exemplaires (une par ville de depart) : on la montre une fois
                for _, c in ipairs(E.ProfQuestList() or {}) do
                    local key = (c.name or "") .. ":" .. tostring(c.s)
                    if not c.done and c.l + 6 >= me and not seen[key] then seen[key] = true; plist[#plist + 1] = c end
                end
            end
            pNone:SetText(T("profNone")); pNone:SetShown(#names > 0 and #plist == 0)
            if #names > 0 and #plist == 0 then at(pNone, 22) end
            for k, b in ipairs(pRows) do
                local c = plist[k]
                if c then
                    b.q = c.q
                    local tag = c.spec and T("profSpec") or (c.dungeon and T("profDungeon") or "")
                    b.fs:SetText(c.name .. tag)
                    local col = (me >= c.r and c.rank) and COL.white or COL.soft
                    if b.fs.SetTextColor then b.fs:SetTextColor(col[1], col[2], col[3]) end
                    b.lv:SetText(T("profLvl", c.r, c.m))
                    b.glow:SetOn((me >= c.r and c.rank) and true or false)
                    at(b, 30); b:Show()
                else
                    b.q = nil; b.glow:SetOn(false); b:Hide()
                end
            end
        end
    end

    -- v1.52 (audit des options, maquette validee par l'auteur) : RÉGLAGES = Guidage · Propositions · Fenetre · Extras.
    -- Chaque onglet repond a une seule question ; les cases « me proposer » sont toutes dans Propositions.

    -- 4. Guidage : fleche, trajets et vols, cartes, ciblage
    do
        local pg = pages[4]
        local y = 0
        local function sec(key) local h = SmallHeader(pg, key); h:SetPoint("TOPLEFT", 0, y); y = y - 18 end
        local function row(r) r:SetPoint("TOPLEFT", 0, y); y = y - ROW_H end
        -- FLECHE
        sec("secArrow")
        -- v1.52 (demande de l'auteur : alleger) : une ligne de choix au lieu de 4 cases. Warpath = notre fleche + le
        -- repere jaune du jeu ; Aucune = pas de fleche (v1.52 : « Celle du jeu » retiree, demande de l'auteur). Fleche intelligente toujours.
        local al = FS(pg, 12, COL.white, FONT, "LEFT"); al:SetPoint("TOPLEFT", 22, y - 7)
        Loc(function() al:SetText(T("arrowLbl")) end)
        local AW = math.floor((CW - 200) / 3) - 4
        for k, mode in ipairs({ "own", "none" }) do
            local r = ChoiceRow(pg, AW, function()
                local was = DB.wp
                DB.wp = (mode ~= "none")
                DB.ownArrow = nil
                DB.gameWP = (mode ~= "none") and true or false
                if mode == "none" then ClearWaypoint() end
                if was ~= DB.wp then E.ResetWP(); Refresh(true) else E.PlaceWaypointAgain() end
                RefreshOptions()
            end)
            r:SetPoint("TOPLEFT", 200 + (k - 1) * (AW + 4), y); r.top:Hide()
            Loc(function() r.label:SetText(T("arrow_" .. mode)) end)
            optRows[#optRows + 1] = function()
                local cur = (not DB.wp) and "none" or "own"
                r:SetChecked(cur == mode)
            end
        end
        y = y - ROW_H - 2
        y = ScaleRow(pg, y, "arrowScale", function() return DB.arrowScale or 1 end, function(v) DB.arrowScale = v end)
        -- (sur sa propre ligne : a cote du reglage de taille, il chevauchait « 100 % »)
        local ra = FlatButton(pg, math.floor((CW - 12) / 2), 24, function() if ns.Arrow then ns.Arrow.Reset() end end)
        ra:SetPoint("TOPLEFT", 22, y)
        Loc(function() ra:SetLabel(Caps(T("arrowReset"))) end)
        if ra.fs.SetFont then ra.fs:SetFont(FONT, 9, "") end
        y = y - 30
        y = y - 6
        -- TRAJETS ET VOLS
        sec("secTrips")
        row(CheckRow(pg, CW, "flyAuto", function() return DB.flyAuto == true end, function(v) DB.flyAuto = v and true or false end))
        row(CheckRow(pg, CW, "hearthTips", function() return DB.hearthTips ~= false end,
            function(v) DB.hearthTips = v; Refresh(true) end))
        y = y - 6
        -- CARTES (repere et chemin ; entraineurs de metier, venus de Metiers)
        sec("secMaps")
        -- v1.52 (alleger) : repere et chemin ensemble, une case par carte (avant : 4 cases)
        row(CheckRow(pg, CW, "mmBoth", function() return DB.mmPin ~= false end, function(v) DB.mmPin = v; DB.mmPath = v end))
        row(CheckRow(pg, CW, "wmBoth", function() return DB.mapPin ~= false end, function(v) DB.mapPin = v; DB.mapPath = v end))
        row(CheckRow(pg, CW, "trainerPinsOpt", function() return DB.trainerPins ~= false end, function(v) DB.trainerPins = v; E.TrainerPins() end))
        y = y - 6
        -- CIBLAGE (la legende des icones passe dans l'infobulle de la case)
        sec("secTargeting")
        local tg = CheckRow(pg, CW, "targets", function() return DB.targets ~= false end, function(v) DB.targets = v; if ns.Targets then ns.Targets.Refresh() end end)
        row(tg)
        tg:SetScript("OnEnter", function(self)
            local function ico(n, r, g, b) return string.format("|TInterface\\AddOns\\OghoulesWarpath\\Media\\%s:12:12:0:0:32:32:0:32:0:32:%d:%d:%d|t", n, r, g, b) end
            E.Tip():SetOwner(self, "ANCHOR_RIGHT"); E.Tip():AddLine(T("targets"))
            E.Tip():AddLine(T("tgtLegend", ico("IcoAccept", 214, 184, 102), ico("IcoTurnin", 156, 199, 168),
                ico("IcoDo", 205, 187, 142), "|TInterface\\Minimap\\Tracking\\FlightMaster:12|t"), 1, 1, 1, true)
            E.Tip():Show()
        end)
    end

    -- 5. Propositions : tout ce que le guide te propose, puis ce qu'il fait pour toi
    do
        local pg = pages[5]
        local y = 0
        local function sec(key) local h = SmallHeader(pg, key); h:SetPoint("TOPLEFT", 0, y); y = y - 18 end
        local function row(r) r:SetPoint("TOPLEFT", 0, y); y = y - ROW_H end
        local function flag(key, field)
            return CheckRow(pg, CW, key, function() return DB[field] ~= false end,
                function(v) DB[field] = v; if field == "trainer" and not v then DB.trainDue = nil end; Refresh(true) end)
        end
        -- ME PROPOSER (venues de Donjons, Classe, Metiers, Itineraire, Comportement)
        sec("secPropose")
        row(CheckRow(pg, CW, "askDungeons", function() return not DB.noDungeonAsk end, function(v) DB.noDungeonAsk = not v end))
        row(CheckRow(pg, CW, "askClass", function() return not DB.noClassAsk end, function(v) DB.noClassAsk = not v end))
        row(CheckRow(pg, CW, "askProf", function() return not DB.noProfAsk end, function(v) DB.noProfAsk = not v end))
        row(flag("dgPickOpt", "dgPick"))
        row(flag("bagOpt", "bagRemind"))
        row(flag("trainerOpt", "trainer"))
        y = y - 10
        -- FAIRE POUR MOI
        sec("secDoForMe")
        for _, o in ipairs({ { "autoQuest", "autoQuest" }, { "itemBtn", "itemBtn" }, { "nearOpt", "near" } }) do row(flag(o[1], o[2])) end
        local note = FS(pg, 10, COL.soft, FONT, "LEFT"); note:SetWidth(CW); note:SetPoint("TOPLEFT", 0, y - 4)
        Loc(function() note:SetText(T("autoNote")) end)
    end

    -- 6. Fenetre : la fenetre du guide, les messages, la langue, le bouton de minicarte
    do
        local pg = pages[6]
        local y = 0
        local function sec(key) local h = SmallHeader(pg, key); h:SetPoint("TOPLEFT", 0, y); y = y - 18 end
        local function row(r) r:SetPoint("TOPLEFT", 0, y); y = y - ROW_H end
        local function flag(key, field, def)
            return CheckRow(pg, CW, key, function() if def then return DB[field] ~= false end return DB[field] and true or false end,
                function(v) DB[field] = v; Refresh(true) end)
        end
        -- FENETRE
        sec("secWindow")
        -- (v1.52, alleger : « Afficher la fenetre » = clic droit sur le bouton de minicarte ou /warpath ;
        -- « Mode compact » = le « - » de la fenetre)
        row(CheckRow(pg, CW, "lock", function() return DB.locked end, function(v) DB.locked = v end))
        y = ScaleRow(pg, y, "scaleWin", function() return DB.scale or 1 end, function(v)
            DB.scale = v
            local f = E.Frame(); if f then f:SetScale(v); local mf = rawget(f, "mini"); if mf then mf:SetScale(v) end end
        end)
        -- (sur sa propre ligne : a cote du reglage de taille, il chevauchait « 100 % »)
        local rp = FlatButton(pg, math.floor((CW - 12) / 2), 24, function()
            DB.wpos = nil
            local f = E.Frame()
            if f then
                f:ClearAllPoints()
                if Minimap then f:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 12, -36)
                else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -240) end
            end
        end)
        rp:SetPoint("TOPLEFT", 22, y)
        Loc(function() rp:SetLabel(Caps(T("resetPos"))) end)
        if rp.fs.SetFont then rp.fs:SetFont(FONT, 9, "") end
        y = y - 30
        y = y - 8
        -- MESSAGES : chat (tous / importants / aucun ; erreurs et commandes toujours), astuces
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
        y = y - 8
        -- LANGUE (venue de Campagne)
        sec("language")
        local rfr = ChoiceRow(pg, 130, function() SetLang("fr") end); rfr:SetPoint("TOPLEFT", 0, y); rfr.top:Hide()
        local ren = ChoiceRow(pg, 130, function() SetLang("en") end); ren:SetPoint("TOPLEFT", 150, y); ren.top:Hide()
        rfr.label:SetText("Français"); ren.label:SetText("English")
        optRows[#optRows + 1] = function() rfr:SetChecked(Lang() == "fr"); ren:SetChecked(Lang() == "en") end
        y = y - ROW_H - 8
        -- MINICARTE
        sec("secMinimap")
        row(CheckRow(pg, CW, "mmButton", function() return not DB.mmHide end,
            function(v) DB.mmHide = not v; if mm then mm:SetShown(v) end end))
    end

    -- 7. Extras : actions sur le guide, visite guidee, Trophees de guerre, Chronique, partage des taux
    do
        local pg = pages[7]
        local y = 0
        local function sec(key) local h = SmallHeader(pg, key); h:SetPoint("TOPLEFT", 0, y); y = y - 18 end
        local function row(r) r:SetPoint("TOPLEFT", 0, y); y = y - ROW_H end
        local BW2 = math.floor((CW - 12) / 2)
        -- LE GUIDE (venus d'Itineraire et de Comportement)
        sec("secGuideActions")
        -- (v1.52, alleger : « Recalculer l'etape » retire, le guide recalcule seul ; reste /warpath now)
        local un = FlatButton(pg, BW2, 28, function() SlashCmdList.WARPATH("unskip all") end)
        un:SetPoint("TOPLEFT", 0, y - 2)
        Loc(function() un:SetLabel(Caps(T("unignore"))) end)
        local tv = FlatButton(pg, BW2, 28, function()
            if opt then opt:Hide() end
            SlashCmdList.WARPATH("tuto")
        end)
        tv:SetPoint("TOPLEFT", BW2 + 12, y - 2)
        Loc(function() tv:SetLabel(Caps(T("tutoReplay"))) end)
        for _, b in ipairs({ un, tv }) do if b.fs.SetFont then b.fs:SetFont(FONT, 9, "") end end
        y = y - 44
        -- TROPHEES DE GUERRE · CHRONIQUE
        sec("hdrExtras")
        row(CheckRow(pg, CW, "pvpShow", function() return not (WarpathDropDB and WarpathDropDB._pvpShow == false) end,
            function(v) if WarpathDropDB then WarpathDropDB._pvpShow = v end; if _G.WarpathPvPRefresh then pcall(_G.WarpathPvPRefresh, true) end end))
        row(CheckRow(pg, CW, "pvpShot", function() return DB.pvpShot and true or false end, function(v) DB.pvpShot = v end))
        row(CheckRow(pg, CW, "chronBanner", function() return DB.chronBanner ~= false end, function(v) DB.chronBanner = v end))
        row(CheckRow(pg, CW, "lvupShow", function() return DB.lvupShow ~= false end, function(v) DB.lvupShow = v end))
        row(CheckRow(pg, CW, "lvupHideUI", function() return DB.lvupHideUI ~= false end, function(v) DB.lvupHideUI = v end))
        local cv = FlatButton(pg, BW2, 28, function() E.ChronShow() end)
        cv:SetPoint("TOPLEFT", 0, y - 4)
        Loc(function() cv:SetLabel(K.Upper(T("chOpen"))) end)
        y = y - 46
        -- PARTAGE (taux de drop anonymes)
        sec("secShare")
        row(CheckRow(pg, CW, "shareOpt", function() return WarpathDropDB and WarpathDropDB._share ~= false end,
            function(v) if WarpathDropDB then WarpathDropDB._share = v end end))
        -- v1.53 : mode equipe (seulement aux membres du groupe)
        row(CheckRow(pg, CW, "teamShareOpt", function() return DB.teamShare ~= false end,
            function(v) DB.teamShare = (not v) and false or nil end))
        row(CheckRow(pg, CW, "teamAskOpt", function() return DB.teamAsk ~= false end,
            function(v) DB.teamAsk = (not v) and false or nil end))
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
