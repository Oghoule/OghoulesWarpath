-- Oghoule's Warpath : fenetres du mode equipe (Team.lua, v1.53, etape 2)
-- Dessine seulement ; la logique est dans Core/Group.lua (vues calculees la-bas).
--   Invite(view)   fenetre « Jouer ensemble » : titre, 2 lignes, 2 boutons TOUJOURS a la meme place et de meme
--                  largeur (la plus longue de tous leurs libelles, en francais et en anglais : texte jamais coupe)
--   Choice(opts, cb)  ecran « Que faites-vous ce soir ? » (celui qui choisit), + « Rester ici »
--   Banner         bandeau « EN EQUIPE · NOM » au-dessus de la fenetre du guide (distance, Quitter)
-- Aucun bouton securise ici (fenetres ordinaires, parent UIParent ou fenetre du guide).
local ADDON, ns = ...
local State = ns.State
local Core = ns.Mod.Core
local Skin = ns.Mod.Skin
local Group = ns.Mod.Group

-- noms propres a ce fichier
local PAD, BTN_H = 16, 28
local LEFT_KEYS, RIGHT_KEYS = { "teamPlay", "teamAccept" }, { "teamSolo", "teamRefuse", "teamCancel" }
local inv, cho, ban

local function Lbl(text) return Skin.Caps(text or "") end

-- largeur des boutons : le plus long libelle possible, dans les deux langues
local function ButtonWidth(fs)
    local w = 0
    for _, keys in ipairs({ LEFT_KEYS, RIGHT_KEYS }) do
        for _, k in ipairs(keys) do
            for _, lang in ipairs({ "fr", "en" }) do
                local t = ns.LANG and ns.LANG[lang] and ns.LANG[lang][k]
                if t then fs:SetText(Lbl(t)); w = math.max(w, (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0) end
            end
        end
    end
    fs:SetText("")
    return math.max(110, math.ceil(w) + 24)
end

local function Panel(w, h)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(w, h)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    local bg = Skin.Tex(f, Skin.COL.bg, 0.96, "BACKGROUND"); bg:SetAllPoints()
    Skin.Border(f, Skin.COL.edge)
    f.title = Skin.FS(f, 11, Skin.COL.accent, Skin.FONT, "LEFT"); f.title:SetPoint("TOPLEFT", PAD, -14)
    f:EnableMouse(true)
    f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    return f
end

local function SetBtn(b, label, on)
    b:SetLabel(Lbl(label))
    if b.SetEnabled then b:SetEnabled(on and true or false) end
    local c = on and Skin.COL.white or Skin.COL.dim
    if b.fs.SetTextColor then b.fs:SetTextColor(c[1], c[2], c[3]) end
end

local function CreateInvite()
    inv = Panel(320, 120)
    inv:SetPoint("TOP", UIParent, "TOP", 0, -170)
    inv.l1 = Skin.FS(inv, 11, Skin.COL.soft, Skin.FONT, "LEFT")
    inv.l2 = Skin.FS(inv, 11, Skin.COL.soft, Skin.FONT, "LEFT")
    inv.L = Skin.FlatButton(inv, 110, BTN_H, function() Group.Click(true) end)
    inv.R = Skin.FlatButton(inv, 110, BTN_H, function() Group.Click(false) end)
end

-- largeur et positions fixees a chaque ouverture (la langue a pu changer) ; jamais pendant une invitation
local GEM = "|TInterface\\AddOns\\OghoulesWarpath\\Media\\Gem:10|t  "
local function Size(peer)
    local bw = ButtonWidth(inv.L.fs)
    local w = math.max(360, 2 * bw + 3 * PAD)
    -- les titres possibles pendant cette invitation tiennent aussi en entier (la fenetre ne change plus de taille)
    for _, t in ipairs({ Core.T("teamUses", peer), Core.T("teamWants", peer), Core.T("teamModeTitle") }) do
        inv.title:SetText(GEM .. Lbl(t))
        local tw = (inv.title.GetUnboundedStringWidth and inv.title:GetUnboundedStringWidth()) or inv.title:GetStringWidth() or 0
        w = math.max(w, math.ceil(tw) + 2 * PAD)
    end
    inv:SetWidth(w)
    for _, fs in ipairs({ inv.title, inv.l1, inv.l2 }) do fs:SetWidth(w - 2 * PAD); if fs.SetWordWrap then fs:SetWordWrap(false) end end
    inv.l1:ClearAllPoints(); inv.l1:SetPoint("TOPLEFT", PAD, -38)
    inv.l2:ClearAllPoints(); inv.l2:SetPoint("TOPLEFT", PAD, -56)
    inv.L:SetSize(bw, BTN_H); inv.L:ClearAllPoints(); inv.L:SetPoint("BOTTOMLEFT", PAD, 14)
    inv.R:SetSize(bw, BTN_H); inv.R:ClearAllPoints(); inv.R:SetPoint("BOTTOMRIGHT", -PAD, 14)
end

local function Invite(v)
    if not inv then CreateInvite() end
    if not inv:IsShown() then
        Size(v.peer or "")
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPEN) end
    end
    inv.title:SetText(GEM .. Lbl(v.title))
    inv.l1:SetText(v.l1 or ""); inv.l2:SetText(v.l2 or "")
    SetBtn(inv.L, v.L, v.lOn); SetBtn(inv.R, v.R, v.rOn)
    inv:Show()
end

local function HideInvite() if inv then inv:Hide() end end

-- ecran de choix (etape 3) : DUREE [1 h][2 h][3 h], plan de la soiree, puis une seule activite, « Rester ici »
local CW = 420
local function Row(h, onClick)
    local b = CreateFrame("Button", nil, cho)
    b:SetSize(CW - 2 * PAD, h)
    Skin.Border(b, Skin.COL.line)
    local hl = Skin.Tex(b, Skin.COL.accent, 0.10, "HIGHLIGHT"); hl:SetAllPoints()
    b.l1 = Skin.FS(b, 12, Skin.COL.white, Skin.FONT, "LEFT"); b.l1:SetPoint("TOPLEFT", 10, -6); b.l1:SetWidth(CW - 2 * PAD - 20)
    b.l2 = Skin.FS(b, 10, Skin.COL.soft, Skin.FONT, "LEFT"); b.l2:SetWidth(CW - 2 * PAD - 20)
    if b.l2.SetWordWrap then b.l2:SetWordWrap(false) end
    b:SetScript("OnClick", onClick)
    return b
end

local function CreateChoice()
    cho = Panel(CW, 300)
    cho:SetPoint("TOP", UIParent, "TOP", 0, -140)
    cho.durLbl = Skin.FS(cho, 9, Skin.COL.gold, Skin.FONT, "LEFT"); cho.durLbl:SetPoint("TOPLEFT", PAD, -42)
    cho.durs = {}
    for k = 1, 3 do
        local b = Skin.FlatButton(cho, 56, 20, function(self) Group.Pick("dur", self.value) end)
        cho.durs[k] = b
    end
    -- le plan : titre, etapes (2 lignes au plus), niveaux prevus
    cho.plan = Row(70, function() Group.Pick("plan") end)
    cho.plan.head = Skin.FS(cho.plan, 9, Skin.COL.gold, Skin.FONT, "LEFT"); cho.plan.head:SetPoint("TOPLEFT", 10, -6)
    cho.plan.l1:ClearAllPoints(); cho.plan.l1:SetPoint("TOPLEFT", 10, -20)
    if cho.plan.l1.SetMaxLines then cho.plan.l1:SetMaxLines(2) end
    cho.plan.l2:SetPoint("TOPLEFT", 10, -52)
    cho.oneLbl = Skin.FS(cho, 9, Skin.COL.gold, Skin.FONT, "LEFT")
    cho.rows = {}
    for k = 1, 3 do
        local b = Row(40, function(self) if self.key then Group.Pick("one", self.key) end end)
        b.l2:SetPoint("TOPLEFT", 10, -23)
        cho.rows[k] = b
    end
    cho.stay = Skin.FlatButton(cho, 160, 24, function() Group.Pick("stay") end)
end

local function Choice(v)
    if not cho then CreateChoice() end
    cho.title:SetText(GEM .. Lbl(Core.T("teamChoiceTitle")))
    cho.durLbl:SetText(Lbl(Core.T("teamDur")))
    local x = PAD + ((cho.durLbl.GetStringWidth and cho.durLbl:GetStringWidth()) or 60) + 12
    for k, b in ipairs(cho.durs) do
        local m = v.durs[k]
        b.value = m
        b:SetLabel(Core.T("teamH", m / 60))
        local c = (m == v.dur) and Skin.COL.accent or Skin.COL.dim
        if b.fs.SetTextColor then b.fs:SetTextColor(c[1], c[2], c[3]) end
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", x + (k - 1) * 62, -36)
    end
    local y = -64
    if v.planL1 then
        cho.plan.head:SetText(Lbl(Core.T("teamPlanHead", Core.T("teamH", v.dur / 60))))
        cho.plan.l1:SetText(v.planL1); cho.plan.l2:SetText(v.planL2 or "")
        cho.plan:ClearAllPoints(); cho.plan:SetPoint("TOPLEFT", PAD, y); cho.plan:Show()
        y = y - 80
    else cho.plan:Hide() end
    cho.oneLbl:SetText(Lbl(Core.T("teamOneHead")))
    cho.oneLbl:ClearAllPoints(); cho.oneLbl:SetPoint("TOPLEFT", PAD, y)
    y = y - 16
    for k = 1, 3 do
        local b, o = cho.rows[k], v.opts[k]
        if o then
            b.key = o.key; b.l1:SetText(o.l1); b.l2:SetText(o.l2)
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", PAD, y); b:Show()
            y = y - 46
        else b.key = nil; b:Hide() end
    end
    cho.stay:SetLabel(Lbl(Core.T("teamStay")))
    cho.stay:ClearAllPoints(); cho.stay:SetPoint("TOPLEFT", PAD, y - 4)
    cho:SetHeight(-y + 44)
    cho:Show()
end

local function HideChoice() if cho then cho:Hide() end end

-- bandeau au-dessus de la fenetre du guide (cree quand la fenetre existe ; mis a jour chaque seconde)
local function UpdateBanner()
    if not Core.f then return end
    local info = Group.BannerInfo and Group.BannerInfo()
    if not info then if ban then ban:Hide() end; return end
    if not ban then
        ban = CreateFrame("Frame", nil, Core.f)
        ban:SetHeight(20)
        ban:SetPoint("BOTTOMLEFT", Core.f, "TOPLEFT", 0, 2); ban:SetPoint("BOTTOMRIGHT", Core.f, "TOPRIGHT", 0, 2)
        local bg = Skin.Tex(ban, Skin.COL.bg, 0.94, "BACKGROUND"); bg:SetAllPoints()
        Skin.Border(ban, Skin.COL.edge)
        ban.name = Skin.FS(ban, 9, Skin.COL.accent, Skin.FONT, "LEFT"); ban.name:SetPoint("LEFT", 8, 0)
        ban.quit = Skin.FlatButton(ban, 64, 16, function() Group.Quit() end)
        ban.quit:SetPoint("RIGHT", -2, 0)
        if ban.quit.fs.SetFont then ban.quit.fs:SetFont(Skin.FONT, 8, "") end
        ban.dist = Skin.FS(ban, 9, Skin.COL.soft, Skin.FONT, "RIGHT"); ban.dist:SetPoint("RIGHT", ban.quit, "LEFT", -6, 0)
    end
    ban.quit:SetLabel(Core.Upper(Core.T("teamQuit")))
    ban.quit:SetWidth(math.max(64, ((ban.quit.fs.GetStringWidth and ban.quit.fs:GetStringWidth()) or 40) + 14))
    ban.name:SetText(Lbl(Core.T("teamBanner", info.name)) .. (info.plan and ("   |cff8c7f62" .. Lbl(Core.T("teamPlanPos", info.plan)) .. "|r") or ""))
    if info.dist and info.dist <= 40 then ban.dist:SetText("|cff9cc7a8" .. Core.T("teamNear") .. "|r")
    elseif info.dist then ban.dist:SetText(Core.T("dist", info.dist))
    else ban.dist:SetText("|cff8c7f62" .. Core.T("teamFar") .. "|r") end
    ban:Show()
end

local function Start()
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, function() pcall(UpdateBanner); pcall(Group.Tick) end) end
end

-- v1.53 : ce que ce fichier offre aux autres (ns.Mod.Team)
do
    local M = ns.Mod.Team
    M.Invite, M.HideInvite, M.Choice, M.HideChoice, M.Start, M.UpdateBanner = Invite, HideInvite, Choice, HideChoice, Start, UpdateBanner
end
