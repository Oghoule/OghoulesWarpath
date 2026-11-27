-- Oghoule's Warpath : moteur (Window.lua) - voir Core.lua
local ADDON, ns = ...
-- v1.50 : etat partage du guide (Core.lua, ns.State)
local State = ns.State
local Window = ns.Mod.Window -- v1.50 : module
local Style = ns.Mod.Style -- v1.50 : module
local Core = ns.Mod.Core -- v1.50 : module
local Perf = ns.Mod.Perf -- v1.50 : module
local Commands = ns.Mod.Commands -- v1.50 : module
local DungeonSheet = ns.Mod.DungeonSheet -- v1.50 : module
local Quartermaster = ns.Mod.Quartermaster -- v1.50 : module
local Profs = ns.Mod.Profs -- v1.50 : module
local Chronicle = ns.Mod.Chronicle -- v1.50 : module
-- v1.50 : module ns.Mod.Window (publie en fin de fichier pour les autres fichiers)
local CreateUI, OnTaxiClosed, OnTaxiOpened, ShowGuide, ToggleMini
local Skin = ns.Mod.Skin -- v1.50 : module
local Flow = ns.Mod.Flow -- v1.50 : module
local Near = ns.Mod.Near -- v1.50 : module
local Est = ns.Mod.Est -- v1.50 : module
local Route = ns.Mod.Route -- v1.50 : module
-- v1.50 : noms propres a ce fichier (sortis de DECL, Core.lua)
local MINI_PAD, MINI_W, NodeKeyFor, distElapsed, taxiGlow, wpElapsed, wpTicker

------------------------------------------------------------------
-- Fenetre (sous la minimap par defaut)
------------------------------------------------------------------
-- v1.46 (rapport du 2026-11-24) : position toujours sauvee par le HAUT de la fenetre (coin haut-gauche ou
-- haut-droit selon le cote de l'ecran), pour qu'elle grandisse vers le bas. Avant : le jeu gardait le point
-- le plus proche au lacher (ex. « RIGHT »), et la fenetre grandissait aussi vers le haut, sur la minicarte.
local function SaveWinPos()
    if not Core.f then return end
    local l, r, t = Core.f:GetLeft(), Core.f:GetRight(), Core.f:GetTop()
    if l and r and t then
        local sw = (UIParent:GetWidth() or 0) * (UIParent:GetEffectiveScale() or 1) / (Core.f:GetEffectiveScale() or 1)
        local left = (l + r) / 2 < sw / 2
        Core.f:ClearAllPoints()
        Core.f:SetPoint(left and "TOPLEFT" or "TOPRIGHT", UIParent, "BOTTOMLEFT", left and l or r, t)
    end
    local p, _, rp, x, y = Core.f:GetPoint()
    State.DB.wpos = { p, rp, x, y }
end

function CreateUI()
    Core.f = CreateFrame("Frame", "WarpathFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    Core.f:SetSize(Skin.W, 200)
    if State.DB.wpos then
        Core.f:SetPoint(State.DB.wpos[1], UIParent, State.DB.wpos[2], State.DB.wpos[3], State.DB.wpos[4])
        -- ancienne position (milieu, bas…) : convertie une fois en position par le haut
        if not tostring(State.DB.wpos[1]):find("^TOP") then pcall(SaveWinPos) end
    elseif Minimap then
        Core.f:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 12, -36)
    else
        Core.f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -240)
    end
    local bg = Skin.Tex(Core.f, Skin.COL.bg, 0.90, "BACKGROUND"); bg:SetAllPoints()
    Skin.Border(Core.f, Skin.COL.line, 0.8, "BORDER")
    -- en-tete : bande un peu plus claire, losange rouge, zone a gauche, etape a droite
    Window.HEAD_H = 34
    local hbg = Skin.Tex(Core.f, Skin.COL.panel, 1, "BORDER"); hbg:SetHeight(Window.HEAD_H); hbg:SetPoint("TOPLEFT", 1, -1); hbg:SetPoint("TOPRIGHT", -1, -1)
    local hln = Skin.Tex(Core.f, Skin.COL.line, 1, "ARTWORK"); hln:SetHeight(1); hln:SetPoint("TOPLEFT", 0, -Window.HEAD_H); hln:SetPoint("TOPRIGHT", 0, -Window.HEAD_H)
    Core.f.gem = Skin.Diamond(Core.f, 8, Skin.COL.red); Core.f.gem:SetPoint("LEFT", Core.f, "TOPLEFT", Skin.PAD - 4, -Window.HEAD_H / 2)
    -- barre de progression de la zone
    Core.f.progBg = Skin.Tex(Core.f, Skin.COL.faint, 1, "ARTWORK"); Core.f.progBg:SetSize(Skin.INNER, 3)
    Core.f.progFill = Skin.Tex(Core.f, Skin.COL.red, 1, "OVERLAY"); Core.f.progFill:SetHeight(3); Core.f.progFill:SetWidth(1); Core.f.progFill:SetPoint("TOPLEFT", Core.f.progBg, "TOPLEFT")
    -- bloc destination : fond un peu plus clair, liseré rouge, fleche, lieu, precision, distance
    Core.f.dest = CreateFrame("Frame", nil, Core.f); Core.f.dest:SetSize(Skin.INNER, 38)
    local dbg = Skin.Tex(Core.f.dest, Skin.COL.panel, 1, "BACKGROUND"); dbg:SetAllPoints()
    local dbar = Skin.Tex(Core.f.dest, Skin.COL.red, 1, "ARTWORK"); dbar:SetWidth(2); dbar:SetPoint("TOPLEFT"); dbar:SetPoint("BOTTOMLEFT")
    Core.f.dest.arrow = Core.f.dest:CreateTexture(nil, "ARTWORK"); Core.f.dest.arrow:SetSize(16, 16); Core.f.dest.arrow:SetPoint("LEFT", 13, 0)
    Core.f.dest.arrow:SetTexture("Interface\\AddOns\\" .. (ADDON or "OghoulesWarpath") .. "\\Media\\IcoNav")
    if Core.f.dest.arrow.SetVertexColor then Core.f.dest.arrow:SetVertexColor(Skin.COL.cream[1], Skin.COL.cream[2], Skin.COL.cream[3]) end
    Core.f.dist = Skin.FS(Core.f.dest, 16, Skin.COL.white, Skin.DISPLAY, "RIGHT"); Core.f.dist:SetPoint("RIGHT", -12, 0)
    Core.f.destName = Skin.FS(Core.f.dest, 12, Skin.COL.white, Skin.FONT, "LEFT"); Core.f.destName:SetPoint("TOPLEFT", 42, -9); Core.f.destName:SetPoint("RIGHT", Core.f.dist, "LEFT", -8, 0)
    -- v1.41 (audit) : le lieu peut tenir sur 2 lignes (avant : coupe avec « … ») ; coordonnees dans l'infobulle
    if Core.f.destName.SetWordWrap then Core.f.destName:SetWordWrap(true) end
    if Core.f.destName.SetMaxLines then Core.f.destName:SetMaxLines(2) end
    if Core.f.dest.EnableMouse then Core.f.dest:EnableMouse(true) end
    if Core.f.dest.RegisterForDrag then Core.f.dest:RegisterForDrag("LeftButton") end
    -- v1.43 : memes gestes que la fenetre (pierre de foyer cachee puis replacee)
    Core.f.dest:SetScript("OnDragStart", function() local fn = Core.f:GetScript("OnDragStart"); if fn then fn(Core.f) end end)
    Core.f.dest:SetScript("OnDragStop", function() local fn = Core.f:GetScript("OnDragStop"); if fn then fn(Core.f) end end)
    Core.f.dest:SetScript("OnEnter", function(self)
        local c = rawget(Core.f, "destCoord"); if not c then return end
        Skin.Tip():SetOwner(self, "ANCHOR_LEFT"); Skin.Tip():AddLine(Core.f.destName:GetText() or "")
        Skin.Tip():AddLine(c, 0.79, 0.75, 0.68); Skin.Tip():Show()
    end)
    Core.f.dest:SetScript("OnLeave", function() Skin.Tip():Hide() end)
    Core.f.dest:Hide()
    Core.f:SetClampedToScreen(true)
    Core.f:SetMovable(true)
    Core.f:EnableMouse(true)
    Core.f:RegisterForDrag("LeftButton")
    -- v1.43 : le bouton de pierre de foyer (securise, hors de la fenetre) se cache pendant le deplacement
    -- et se replace sur l'icone au lacher, hors combat (en combat : replace a la fin du combat)
    Core.f:SetScript("OnDragStart", function(self)
        if State.DB.locked then return end
        local b = rawget(self, "hsBtn")
        if b and not (InCombatLockdown and InCombatLockdown()) then b:Hide() end
        self:StartMoving()
    end)
    Core.f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveWinPos()
        if Window.HearthPlace then pcall(Window.HearthPlace) end
    end)

    -- (ordre de creation garde : title, text, list, coord)
    -- v1.41 : le titre s'arrete avant les icones de droite (« - » et Intendance) : il ne chevauche plus rien
    Core.f.title = Skin.FS(Core.f, 12, Skin.COL.white, Skin.FONT, "LEFT"); Core.f.title:SetPoint("LEFT", Core.f, "TOPLEFT", Skin.PAD + 12, -Window.HEAD_H / 2)
    Core.f.title:SetPoint("RIGHT", Core.f, "TOPRIGHT", -44, -Window.HEAD_H / 2)
    if Core.f.title.SetWordWrap then Core.f.title:SetWordWrap(false) end
    -- numero d'etape : juste au-dessus de la barre de progression de la zone (avant : dans l'en-tete, sous le titre)
    Core.f.stepNo = Skin.FS(Core.f, 11, Skin.COL.soft, Skin.FONT, "RIGHT"); Core.f.stepNo:SetPoint("BOTTOMRIGHT", Core.f.progBg, "TOPRIGHT", 0, 4)
    Core.f.text = Skin.FS(Core.f, 12, Skin.COL.soft, Skin.FONT, "LEFT"); Core.f.text:SetWidth(Skin.INNER)
    if Core.f.text.SetJustifyV then Core.f.text:SetJustifyV("TOP") end
    if Core.f.text.SetWordWrap then Core.f.text:SetWordWrap(true) end
    if Core.f.text.SetSpacing then Core.f.text:SetSpacing(4) end
    Core.f.nextRule = Skin.SectionHead(Core.f, Skin.INNER)
    Core.f.list = Core.f.nextRule.label
    -- v1.41 : « +2 ▾ » a droite de « A SUIVRE » : deplier / replier la liste (2 ou 4 etapes)
    Core.f.upToggle = CreateFrame("Button", nil, Core.f.nextRule); Core.f.upToggle:SetSize(44, 14); Core.f.upToggle:SetPoint("RIGHT", Core.f.nextRule, "RIGHT", 0, 0)
    local utb = Skin.Tex(Core.f.upToggle, Skin.COL.bg, 1, "BACKGROUND"); utb:SetAllPoints()
    Core.f.upToggle.fs = Skin.FS(Core.f.upToggle, 10, Skin.COL.accent, Skin.FONT, "RIGHT"); Core.f.upToggle.fs:SetPoint("RIGHT", -1, 0)
    local uth = Skin.Tex(Core.f.upToggle, Skin.COL.accent, 0.10, "HIGHLIGHT"); uth:SetAllPoints()
    Core.f.upToggle:SetScript("OnClick", function()
        -- v1.52 : « LA SUITE » repliee : « +N » la rouvre ; sinon 2 ou 4 etapes comme avant
        if State.DB.upHidden then State.DB.upHidden = nil else State.DB.upOpen = not State.DB.upOpen end
        Skin.Refresh()
    end)
    Core.f.upToggle:Hide()
    Core.f.coord = Skin.FS(Core.f.dest, 11, Skin.COL.soft, Skin.FONT, "LEFT"); Core.f.coord:SetPoint("TOPLEFT", Core.f.destName, "BOTTOMLEFT", 0, -5); Core.f.coord:SetPoint("RIGHT", Core.f.dist, "LEFT", -8, 0)
    if Core.f.coord.SetWordWrap then Core.f.coord:SetWordWrap(false) end
    -- pied : niveau, XP/h actif (Journal.lua), duree de la session
    Core.f.foot = CreateFrame("Frame", nil, Core.f); Core.f.foot:SetSize(Skin.INNER, 14); Core.f.foot:Hide()
    Core.f.footLvl = Skin.FS(Core.f.foot, 11, Skin.COL.gold, Skin.FONT, "LEFT"); Core.f.footLvl:SetPoint("LEFT")
    Core.f.xph = Skin.FS(Core.f.foot, 11, Skin.COL.gold, Skin.FONT, "CENTER"); Core.f.xph:SetPoint("CENTER"); Core.f.xph:Hide()
    Core.f.footSess = Skin.FS(Core.f.foot, 11, Skin.COL.gold, Skin.FONT, "RIGHT"); Core.f.footSess:SetPoint("RIGHT")
    if Core.f.foot.EnableMouse then Core.f.foot:EnableMouse(true) end
    Core.f.foot:SetScript("OnEnter", function(self)
        local i = rawget(Core.f, "footInfo"); if type(i) ~= "table" then return end
        local t = Skin.Tip(); t:SetOwner(self, "ANCHOR_TOP")
        t:AddLine(Core.T("footTipHead"))
        t:AddLine(Core.T("footTipActive", i.rate > 0 and Est.FormatNum(math.floor(i.rate)) or "—", i.active), 1, 1, 1, true)
        t:AddLine(Core.T("footTipWall", i.wallRate > 0 and Est.FormatNum(math.floor(i.wallRate)) or "—", i.wall), 1, 1, 1, true)
        t:AddLine(Core.T("footTipNote"), 0.66, 0.60, 0.48, true)
        t:Show()
    end)
    Core.f.foot:SetScript("OnLeave", function() Skin.Tip():Hide() end)
    -- v1.41 : niveau, XP/h et temps avant le niveau suivant au survol de la barre de progression (le pied a disparu)
    Core.f.progHit = CreateFrame("Frame", nil, Core.f)
    Core.f.progHit:SetPoint("TOPLEFT", Core.f.progBg, "TOPLEFT", 0, 16); Core.f.progHit:SetPoint("BOTTOMRIGHT", Core.f.progBg, "BOTTOMRIGHT", 0, -4)
    if Core.f.progHit.EnableMouse then Core.f.progHit:EnableMouse(true) end
    Core.f.progHit:SetScript("OnEnter", function(self)
        local i = rawget(Core.f, "footInfo")
        local t = Skin.Tip(); t:SetOwner(self, "ANCHOR_BOTTOM")
        t:AddLine((type(i) == "table" and i.lvl) or Core.T("footLvl", UnitLevel("player") or 1, 0))
        if type(i) == "table" then
            if i.xph and i.xph ~= "" then t:AddLine(i.xph, 1, 1, 1) end
            if i.nxt and i.nxt ~= "" then t:AddLine(i.nxt, 1, 1, 1) end
            t:AddLine(Core.T("footTipActive", i.rate > 0 and Est.FormatNum(math.floor(i.rate)) or "—", i.active), 0.79, 0.75, 0.68, true)
            t:AddLine(Core.T("footTipNote"), 0.66, 0.60, 0.48, true)
        end
        t:Show()
    end)
    Core.f.progHit:SetScript("OnLeave", function() Skin.Tip():Hide() end)
    -- v1.52 (audit) : parcours choisi (Bande de guerre / Eclaireur), a gauche au-dessus de la barre, en face de
    -- « Etape x / y » ; clic = ecran de choix du parcours (texte remis par SetHeader, Skin.lua)
    Core.f.routeBtn = CreateFrame("Button", nil, Core.f); Core.f.routeBtn:SetSize(100, 14)
    Core.f.routeBtn:SetPoint("BOTTOMLEFT", Core.f.progBg, "TOPLEFT", 0, 2)
    if Core.f.routeBtn.SetFrameLevel and Core.f.progHit.GetFrameLevel then Core.f.routeBtn:SetFrameLevel((Core.f.progHit:GetFrameLevel() or 1) + 2) end
    Core.f.routeBtn.gem = Skin.Diamond(Core.f.routeBtn, 6, Skin.COL.red); Core.f.routeBtn.gem:SetPoint("LEFT", 0, 0)
    Core.f.routeBtn.fs = Skin.FS(Core.f.routeBtn, 10, Skin.COL.gold, Skin.FONT, "LEFT"); Core.f.routeBtn.fs:SetPoint("LEFT", 11, 0)
    local rbh = Skin.Tex(Core.f.routeBtn, Skin.COL.accent, 0.10, "HIGHLIGHT"); rbh:SetAllPoints()
    Core.f.routeBtn:SetScript("OnClick", function() if SlashCmdList and SlashCmdList.WARPATH then SlashCmdList.WARPATH("parcours") end end)
    Core.f.routeBtn:SetScript("OnEnter", function(self)
        local wb = Core.Parcours() == "warband"
        local t = Skin.Tip(); t:SetOwner(self, "ANCHOR_BOTTOM")
        t:AddLine(Core.T(wb and "routeWarband" or "routeScout"))
        t:AddLine(Core.T(wb and "routeWarbandTip" or "routeScoutTip"), 1, 1, 1, true)
        t:AddLine(Core.T("routeBtnTip"), 0.66, 0.60, 0.48, true)
        t:Show()
    end)
    Core.f.routeBtn:SetScript("OnLeave", function() Skin.Tip():Hide() end)
    Core.f.routeBtn:Hide()

    Core.f.name = Skin.FS(Core.f, 13, Skin.COL.white, Skin.FONT, "CENTER"); Core.f.name:SetWidth(Skin.INNER); Core.f.name:Hide() -- (garde pour les tests)
    Core.f.div = Skin.Divider(Core.f, Skin.INNER); Core.f.div:Hide()
    -- badge du niveau de la quete
    Core.f.badge = CreateFrame("Frame", nil, Core.f); Core.f.badge:SetSize(32, 46)
    local bb = CreateFrame("Frame", nil, Core.f.badge); bb:SetSize(32, 32); bb:SetPoint("TOP")
    Skin.Border(bb, Skin.COL.accent)
    Core.f.badge.num = Skin.FS(bb, 13, Skin.COL.cream, Skin.FONT, "CENTER"); Core.f.badge.num:SetPoint("CENTER", 0, 0)
    Core.f.badge.lbl = Skin.FS(Core.f.badge, 9, Skin.COL.gold, Skin.FONT, "CENTER"); Core.f.badge.lbl:SetPoint("TOP", bb, "BOTTOM", 0, -4)
    if Core.f.badge.EnableMouse then Core.f.badge:EnableMouse(true) end
    Core.f.badge:SetScript("OnEnter", function(self)
        Skin.Tip():SetOwner(self, "ANCHOR_LEFT")
        Skin.Tip():AddLine(Core.T("badgeTip", tonumber(Core.f.badge.num:GetText()) or 0, UnitLevel("player") or 1))
        if type(Core.f.rateTip) == "string" then Skin.Tip():AddLine(Core.f.rateTip, 0.84, 0.72, 0.40) end
        Skin.Tip():Show()
    end)
    Core.f.badge:SetScript("OnLeave", function() Skin.Tip():Hide() end)
    Core.f.badge:Hide()

    Core.f.kindRow = CreateFrame("Frame", nil, Core.f); Core.f.kindRow:SetSize(Skin.INNER, 14)
    Core.f.kind = Skin.FS(Core.f.kindRow, 11, Skin.COL.accent, Skin.FONT, "LEFT"); Core.f.kind:SetPoint("LEFT")
    if Core.f.kind.SetWordWrap then Core.f.kind:SetWordWrap(false) end
    -- clic sur l'en-tete (le crochet) d'une etape passee ou validee a la main : on l'annule
    if Core.f.kindRow.EnableMouse then Core.f.kindRow:EnableMouse(true) end
    Core.f.kindRow:SetScript("OnMouseUp", function()
        local i = State.peek or State.focus or State.current
        if State.steps and i and Flow.Restorable(i) then Flow.Restore(i) end
    end)
    -- v1.41 (audit, proposition A) : chaine et quetes bloquees = deux pastilles a droite de la ligne du type
    -- d'etape (detail au survol, meme clic qu'avant) au lieu de deux lignes pleines
    local function chip(icon, col)
        local b = CreateFrame("Button", nil, Core.f.kindRow); b:SetSize(36, 14)
        if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
        Skin.Border(b, col, 0.45)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(10, 10); b.icon:SetPoint("LEFT", 3, 0)
        b.icon:SetTexture("Interface\\AddOns\\" .. (ADDON or "OghoulesWarpath") .. "\\Media\\" .. icon)
        if b.icon.SetVertexColor then b.icon:SetVertexColor(col[1], col[2], col[3]) end
        b.fs = Skin.FS(b, 10, col, Skin.FONT, "LEFT"); b.fs:SetPoint("LEFT", 16, 0)
        local h = Skin.Tex(b, col, 0.12, "HIGHLIGHT"); h:SetAllPoints()
        b:SetScript("OnLeave", function() Skin.Tip():Hide() end)
        b:Hide()
        return b
    end
    Core.f.chipLock = chip("IcoLock", Skin.COL.warn or Skin.COL.accent)
    Core.f.chipChain = chip("IcoChain", Skin.COL.accent)
    -- memes actions que les anciennes lignes (f.chainBtn / f.lockBtn, gardees cachees pour leur logique)
    Core.f.chipChain:SetScript("OnClick", function() local fn = Core.f.chainBtn and Core.f.chainBtn:GetScript("OnClick"); if fn then fn(Core.f.chainBtn) end end)
    Core.f.chipChain:SetScript("OnEnter", function(self)
        Skin.Tip():SetOwner(self, "ANCHOR_LEFT"); Skin.Tip():AddLine(self.tipText or "")
        if Core.f.chainBtn and Core.f.chainBtn.target then Skin.Tip():AddLine(Core.T("chainStart"), 0.66, 0.60, 0.48, true) end
        Skin.Tip():Show()
    end)
    Core.f.chipLock:SetScript("OnClick", function(_, btn) local fn = Core.f.lockBtn and Core.f.lockBtn:GetScript("OnClick"); if fn then fn(Core.f.lockBtn, btn) end end)
    Core.f.chipLock:SetScript("OnEnter", function(self)
        local fn = Core.f.lockBtn and Core.f.lockBtn:GetScript("OnEnter")
        if fn then self.list = Core.f.lockBtn.list; fn(self) end
    end)

    Core.f.qtitle = Skin.FS(Core.f, 20, Skin.COL.white, Skin.DISPLAY, "LEFT"); Core.f.qtitle:SetWidth(Skin.INNER)
    if Core.f.qtitle.SetTextColor then Core.f.qtitle:SetTextColor(0.95, 0.89, 0.72) end
    Core.f.qsub = Skin.FS(Core.f, 11, Skin.COL.soft, Skin.FONT, "LEFT"); Core.f.qsub:SetWidth(Skin.INNER); Core.f.qsub:Hide()
    -- survol du titre : texte complet de l'etape (quand la fenetre montre les objectifs en direct)
    Core.f.qhit = CreateFrame("Frame", nil, Core.f); Core.f.qhit:SetAllPoints(Core.f.qtitle); Core.f.qhit:EnableMouse(true)
    Core.f.qhit:SetScript("OnEnter", function(self)
        if type(Core.f.qtitleTip) ~= "string" and type(Core.f.rateTip) ~= "string" and type(Core.f.tipText) ~= "string" then return end
        Skin.Tip():SetOwner(self, "ANCHOR_LEFT")
        if type(Core.f.qtitleTip) == "string" then Skin.Tip():AddLine(Core.f.qtitleTip, 1, 1, 1, true) end
        if type(Core.f.tipText) == "string" then Skin.Tip():AddLine(" "); Skin.Tip():AddLine(Core.T("tipLbl"), 0.84, 0.72, 0.40); Skin.Tip():AddLine(Core.f.tipText, 1, 1, 1, true) end
        if type(Core.f.rateTip) == "string" then Skin.Tip():AddLine(Core.f.rateTip, 0.84, 0.72, 0.40) end
        Skin.Tip():AddLine(Core.T("qtitleClick"), 0.66, 0.60, 0.48, true); Skin.Tip():Show()
    end)
    Core.f.qhit:SetScript("OnLeave", function() Skin.Tip():Hide() end)
    Core.f.qhit:SetScript("OnMouseDown", function(_, btn)
        Core.f.qdown = { GetCursorPosition() }
        if btn == "LeftButton" and not State.DB.locked and Core.f.StartMoving then Core.f:StartMoving() end
    end)
    Core.f.qhit:SetScript("OnMouseUp", function(_, btn)
        if Core.f.StopMovingOrSizing then Core.f:StopMovingOrSizing() end
        SaveWinPos()
        local cx, cy = GetCursorPosition()
        local d = Core.f.qdown and math.abs(cx - (Core.f.qdown[1] or cx)) + math.abs(cy - (Core.f.qdown[2] or cy)) or 0
        if btn == "LeftButton" and d < 4 and Flow.OpenStepQuest then Flow.OpenStepQuest() end
    end)
    if Core.f.qtitle.SetWordWrap then Core.f.qtitle:SetWordWrap(true) end

    Core.f.route = {}
    for k = 1, 3 do
        local row = CreateFrame("Frame", nil, Core.f); row:SetSize(Skin.INNER, 16)
        row.gem = Skin.Diamond(row, 7, Skin.COL.white); row.gem:SetPoint("LEFT", -2, 0)
        row.mode = Skin.FS(row, 10, Skin.COL.accent, Skin.FONT, "RIGHT"); row.mode:SetPoint("RIGHT")
        row.name = Skin.FS(row, 12, Skin.COL.white, Skin.FONT, "LEFT"); row.name:SetPoint("LEFT", 16, 0); row.name:SetPoint("RIGHT", row.mode, "LEFT", -6, 0)
        if row.name.SetWordWrap then row.name:SetWordWrap(false) end
        row:Hide()
        Core.f.route[k] = row
    end

    Core.f.chainBtn = CreateFrame("Button", nil, Core.f); Core.f.chainBtn:SetSize(Skin.INNER, 16)
    Core.f.chainBtn.label = Skin.FS(Core.f.chainBtn, 11, Skin.COL.accent, Skin.FONT, "LEFT"); Core.f.chainBtn.label:SetPoint("LEFT")
    local hl = Skin.Tex(Core.f.chainBtn, Skin.COL.accent, 0.08, "HIGHLIGHT"); hl:SetAllPoints()
    Core.f.chainBtn.gems = {}
    for k = 10, 1, -1 do
        local g = Skin.Diamond(Core.f.chainBtn, 5, Skin.COL.line, true)
        g:SetPoint("RIGHT", Core.f.chainBtn, "RIGHT", -(10 - k) * 9, 0)
        Core.f.chainBtn.gems[k] = g
    end
    Core.f.chainBtn:SetScript("OnClick", function(self)
        if self.target then State.focus = self.target; State.peek = nil; State.lastWP = nil; Skin.Refresh(true) end
    end)
    Core.f.chainBtn:SetScript("OnEnter", function(self)
        if not self.target then return end
        Skin.Tip():SetOwner(self, "ANCHOR_LEFT")
        Skin.Tip():AddLine(Core.T("chainStart"))
        Skin.Tip():Show()
    end)
    Core.f.chainBtn:SetScript("OnLeave", function() Skin.Tip():Hide() end)
    Core.f.chainBtn:Hide()

    -- v1.52 (audit A) : etape « Donjon » : bouton qui ouvre la fiche du donjon (Features/DungeonSheet.lua)
    Core.f.dsBtn = Skin.FlatButton(Core.f, Skin.INNER, 24, function(self)
        local DS = ns.Mod.DungeonSheet
        if self.key and DS and DS.DungeonSheetOpen then DS.DungeonSheetOpen(self.key) end
    end)
    if Core.f.dsBtn.fs.SetFont then Core.f.dsBtn.fs:SetFont(Skin.FONT, 9, ""); Core.f.dsBtn.fs:SetTextColor(Skin.COL.accent[1], Skin.COL.accent[2], Skin.COL.accent[3]) end
    Core.f.dsBtn:Hide()
    -- v1.52 (audit C) : « Autour de toi » : quetes en attente de niveau, notes du lieu, quetes en chemin,
    -- repliees par defaut (DB.aroundOpen) ; un clic sur la ligne deplie / replie
    Core.f.aroundBtn = CreateFrame("Button", nil, Core.f); Core.f.aroundBtn:SetSize(Skin.INNER, 14)
    Core.f.aroundBtn.label = Skin.FS(Core.f.aroundBtn, 10, Skin.COL.gold, Skin.FONT, "LEFT"); Core.f.aroundBtn.label:SetPoint("LEFT")
    Core.f.aroundBtn.right = Skin.FS(Core.f.aroundBtn, 10, Skin.COL.accent, Skin.FONT, "RIGHT"); Core.f.aroundBtn.right:SetPoint("RIGHT", -1, 0)
    local arh = Skin.Tex(Core.f.aroundBtn, Skin.COL.accent, 0.08, "HIGHLIGHT"); arh:SetAllPoints()
    Core.f.aroundBtn:SetScript("OnClick", function() State.DB.aroundOpen = not State.DB.aroundOpen; Skin.Refresh() end)
    Core.f.aroundBtn:Hide()
    -- v1.52 (demande de l'auteur) : parties repliables directement dans la fenetre (remplace l'option
    -- « Fenetre allegee ») : titre « DETAILS » au-dessus du texte (DB.detailsHidden), titre « LA SUITE » (DB.upHidden)
    local function foldHead(onClick)
        local b = CreateFrame("Button", nil, Core.f); b:SetSize(Skin.INNER, 14)
        b.label = Skin.FS(b, 10, Skin.COL.gold, Skin.FONT, "LEFT"); b.label:SetPoint("LEFT")
        b.right = Skin.FS(b, 10, Skin.COL.accent, Skin.FONT, "RIGHT"); b.right:SetPoint("RIGHT", -1, 0)
        local hl = Skin.Tex(b, Skin.COL.accent, 0.08, "HIGHLIGHT"); hl:SetAllPoints()
        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(self) Skin.Tip():SetOwner(self, "ANCHOR_LEFT"); Skin.Tip():AddLine(Core.T("foldTip"), 1, 1, 1, true); Skin.Tip():Show() end)
        b:SetScript("OnLeave", function() Skin.Tip():Hide() end)
        b:Hide()
        return b
    end
    Core.f.textHead = foldHead(function() State.DB.detailsHidden = not State.DB.detailsHidden or nil; Skin.Refresh() end)
    -- titre « LA SUITE » cliquable (le « +2 / - » a droite garde son role : 2 ou 4 etapes)
    Core.f.nextHit = CreateFrame("Button", nil, Core.f.nextRule)
    Core.f.nextHit:SetPoint("TOPLEFT", Core.f.nextRule, "TOPLEFT"); Core.f.nextHit:SetPoint("BOTTOMRIGHT", Core.f.nextRule, "BOTTOMRIGHT", -48, 0)
    local nhh = Skin.Tex(Core.f.nextHit, Skin.COL.accent, 0.08, "HIGHLIGHT"); nhh:SetAllPoints()
    Core.f.nextHit:SetScript("OnClick", function() State.DB.upHidden = not State.DB.upHidden or nil; Skin.Refresh() end)
    Core.f.nextHit:SetScript("OnEnter", function(self) Skin.Tip():SetOwner(self, "ANCHOR_LEFT"); Skin.Tip():AddLine(Core.T("foldTip"), 1, 1, 1, true); Skin.Tip():Show() end)
    Core.f.nextHit:SetScript("OnLeave", function() Skin.Tip():Hide() end)
    -- ancienne option « Fenetre allegee » (DB.compact) : devient « LA SUITE » repliee
    if State.DB.compact then State.DB.upHidden = true; State.DB.compact = nil end
    -- v1.52 (options allegees) : fleche intelligente et vols connus toujours actifs (cases retirees) ;
    -- repere et chemin reunis en une case par carte : le chemin suit le repere
    State.DB.smartArrow, State.DB.useFlights, State.DB.ownArrow = nil, nil, nil   -- (et fleche Warpath : « celle du jeu » retiree)
    State.DB.mmPath = (State.DB.mmPin == false) and false or nil
    State.DB.mapPath = (State.DB.mapPin == false) and false or nil
    Core.f.aroundText = Skin.FS(Core.f, 11, Skin.COL.soft, Skin.FONT, "LEFT"); Core.f.aroundText:SetWidth(Skin.INNER)
    if Core.f.aroundText.SetJustifyV then Core.f.aroundText:SetJustifyV("TOP") end
    if Core.f.aroundText.SetWordWrap then Core.f.aroundText:SetWordWrap(true) end
    if Core.f.aroundText.SetSpacing then Core.f.aroundText:SetSpacing(3) end
    Core.f.aroundText:Hide()

    -- conseil (journal plein, pierre de foyer)
    Core.f.advice = CreateFrame("Frame", nil, Core.f); Core.f.advice:SetSize(Skin.INNER, 16)
    Core.f.advice.icon = Core.f.advice:CreateTexture(nil, "ARTWORK"); Core.f.advice.icon:SetSize(14, 14); Core.f.advice.icon:SetPoint("TOPLEFT", 0, -1)
    Core.f.advice.label = Skin.FS(Core.f.advice, 11, Skin.COL.gold, Skin.FONT, "LEFT"); Core.f.advice.label:SetPoint("TOPLEFT", 20, -2)
    Core.f.advice.label:SetWidth(Skin.INNER - 20); if Core.f.advice.label.SetWordWrap then Core.f.advice.label:SetWordWrap(true) end
    Core.f.advice:Hide()
    -- pierre de foyer : l'icone du conseil devient un bouton qui l'utilise (bouton securise).
    -- v1.41 : le bouton n'est PLUS un enfant de la fenetre ni ancre a elle. Un bouton securise dans la fenetre
    -- la verrouille en combat : SetHeight / SetShown / Hide etaient bloques sans arret en donjon. On recopie la
    -- position de l'icone hors combat (comme les boutons de ciblage) et on le cache a l'entree en combat.
    function Window.HearthButton(on)
        Core.f.hsWant = on and true or false
        Core.f.advice.icon:SetSize(on and 18 or 14, on and 18 or 14)
        Core.f.advice.label:ClearAllPoints(); Core.f.advice.label:SetPoint("TOPLEFT", on and 26 or 20, on and -4 or -2)
        if InCombatLockdown and InCombatLockdown() then return end
        if not Core.f.hsBtn and on then
            local ok, b = pcall(CreateFrame, "Button", "WarpathHearthButton", UIParent, "SecureActionButtonTemplate")
            if not ok or not b then return end
            b:SetSize(18, 18)
            if b.SetFrameStrata then b:SetFrameStrata("HIGH") end
            if b.RegisterForClicks then b:RegisterForClicks("AnyUp", "AnyDown") end
            b:SetAttribute("type", "item"); b:SetAttribute("item", "item:6948")
            local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.25)
            Skin.Border(b, Skin.COL.accent)
            b:SetScript("OnEnter", function(self) Skin.Tip():SetOwner(self, "ANCHOR_LEFT"); Skin.Tip():AddLine(Core.T("hsClick")); Skin.Tip():Show() end)
            b:SetScript("OnLeave", function() Skin.Tip():Hide() end)
            b:Hide()
            Core.f.hsBtn = b
        end
    end
    -- place le bouton sur l'icone (apres la mise en page), hors combat seulement
    function Window.HearthPlace()
        local b = rawget(Core.f, "hsBtn")
        if not b or (InCombatLockdown and InCombatLockdown()) then return end
        local ic = Core.f.advice.icon
        local want = Core.f.hsWant and Core.f:IsShown() and Core.f.advice:IsShown()
        local l, bot = want and ic.GetLeft and ic:GetLeft(), want and ic.GetBottom and ic:GetBottom()
        if not (l and bot) then b:Hide(); return end
        local k = (Core.f.GetEffectiveScale and UIParent.GetEffectiveScale) and (Core.f:GetEffectiveScale() / UIParent:GetEffectiveScale()) or 1
        b:SetScale(1); b:SetSize(18 * k, 18 * k)
        b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * k, bot * k)
        b:Show()
    end
    -- entree en combat : on le cache juste avant le verrouillage (il ne sert a rien en combat)
    local hsEv = CreateFrame("Frame")
    hsEv:RegisterEvent("PLAYER_REGEN_DISABLED")
    hsEv:RegisterEvent("PLAYER_REGEN_ENABLED")
    hsEv:SetScript("OnEvent", function(_, e)
        local b = rawget(Core.f, "hsBtn")
        if e == "PLAYER_REGEN_DISABLED" then if b then b:Hide() end
        else pcall(Window.HearthPlace) end
    end)

    Core.f.lockBtn = CreateFrame("Button", nil, Core.f); Core.f.lockBtn:SetSize(Skin.INNER, 16)
    if Core.f.lockBtn.RegisterForClicks then Core.f.lockBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    local lbg = Skin.Tex(Core.f.lockBtn, Skin.COL.warn, 0.08, "BACKGROUND"); lbg:SetAllPoints()
    Skin.Border(Core.f.lockBtn, Skin.COL.warn, 0.35)
    Core.f.lockBtn.gem = Skin.Diamond(Core.f.lockBtn, 7, Skin.COL.warn); Core.f.lockBtn.gem:SetPoint("LEFT", 7, 0)
    Core.f.lockBtn.label = Skin.FS(Core.f.lockBtn, 11, Skin.COL.accent, Skin.FONT, "LEFT"); Core.f.lockBtn.label:SetPoint("LEFT", 22, 0)
    Core.f.lockBtn.label:SetWidth(Skin.INNER - 26); if Core.f.lockBtn.label.SetWordWrap then Core.f.lockBtn.label:SetWordWrap(true) end
    Core.f.lockBtn.label:SetPoint("RIGHT", -6, 0)
    if Core.f.lockBtn.label.SetWordWrap then Core.f.lockBtn.label:SetWordWrap(false) end
    local lhl = Skin.Tex(Core.f.lockBtn, Skin.COL.accent, 0.08, "HIGHLIGHT"); lhl:SetAllPoints()
    -- grotte : effacer une entree mal apprise (porte de maison prise pour l'entree)
    Core.f.caveBtn = CreateFrame("Button", nil, Core.f); Core.f.caveBtn:SetSize(Skin.INNER, 16)
    Core.f.caveBtn.gem = Skin.Diamond(Core.f.caveBtn, 6, Skin.COL.gold); Core.f.caveBtn.gem:SetPoint("LEFT", -1, 0)
    Core.f.caveBtn.label = Skin.FS(Core.f.caveBtn, 11, Skin.COL.accent, Skin.FONT, "LEFT"); Core.f.caveBtn.label:SetPoint("LEFT", 14, 0)
    local chl = Skin.Tex(Core.f.caveBtn, Skin.COL.accent, 0.08, "HIGHLIGHT"); chl:SetAllPoints()
    Core.f.caveBtn:SetScript("OnClick", function() if Near.ForgetCave then Near.ForgetCave() end end)
    Core.f.caveBtn:SetScript("OnEnter", function(self)
        Skin.Tip():SetOwner(self, "ANCHOR_LEFT"); Skin.Tip():AddLine(Core.T("caveWrong")); Skin.Tip():AddLine(Core.T("caveWrongTip"), 0.66, 0.60, 0.48, true); Skin.Tip():Show()
    end)
    Core.f.caveBtn:SetScript("OnLeave", function() Skin.Tip():Hide() end)
    Core.f.caveBtn:Hide()
    Core.f.lockBtn:SetScript("OnClick", function(self, button)
        local i = self.idx
        if not i then return end
        if button == "RightButton" then
            State.DB.lockHide[State.steps[i].id] = true
            Skin.Refresh()
        else
            Flow.AskChain(State.steps[i].id)
        end
    end)
    Core.f.lockBtn:SetScript("OnEnter", function(self)
        Skin.Tip():SetOwner(self, "ANCHOR_LEFT")
        Skin.Tip():AddLine(Core.T("lockTitle"))
        for _, i in ipairs(self.list or {}) do
            local miss = {}
            for _, q in ipairs(Core.blockedBy[i] or {}) do miss[#miss + 1] = (Est.EST[q] and Est.EST[q].n) or tostring(q) end
            Skin.Tip():AddLine((Core.QName(State.steps[i]) or "?") .. "  |cff8c7f62(" .. table.concat(miss, ", ") .. ")|r", 0.84, 0.60, 0.40)
        end
        Skin.Tip():AddLine(Core.T("lockTip"), 0.66, 0.60, 0.48, true)
        Skin.Tip():Show()
    end)
    Core.f.lockBtn:SetScript("OnLeave", function() Skin.Tip():Hide() end)
    Core.f.lockBtn:Hide()

    -- en regardant d'autres etapes (< > ou clic dans la liste) : retour a l'etape actuelle en un clic
    Core.f.nowBtn = CreateFrame("Button", nil, Core.f); Core.f.nowBtn:SetSize(Skin.INNER, 18)
    local nbg = Skin.Tex(Core.f.nowBtn, Skin.COL.accent, 0.10, "BACKGROUND"); nbg:SetAllPoints()
    Core.f.nowBtn.gem = Skin.Diamond(Core.f.nowBtn, 6, Skin.COL.accent); Core.f.nowBtn.gem:SetPoint("LEFT", 4, 0)
    Core.f.nowBtn.label = Skin.FS(Core.f.nowBtn, 11, Skin.COL.accent, Skin.FONT, "LEFT"); Core.f.nowBtn.label:SetPoint("LEFT", 16, 0)
    local nhl = Skin.Tex(Core.f.nowBtn, Skin.COL.accent, 0.12, "HIGHLIGHT"); nhl:SetAllPoints()
    Core.f.nowBtn:SetScript("OnClick", function() if Flow.BackToNow then Flow.BackToNow() end end)
    Core.f.nowBtn:Hide()

    Core.f.btnRow = CreateFrame("Frame", nil, Core.f); Core.f.btnRow:SetSize(Skin.INNER, 34)
    -- clic gauche : etape precedente / suivante ; clic droit : retour a l'etape actuelle (un seul des deux)
    local function nav(d) return function(_, btn) if btn == "RightButton" then if Flow.BackToNow then Flow.BackToNow() end else Flow.Peek(d) end end end
    local prev = Skin.FlatButton(Core.f.btnRow, 46, 34, nav(-1)); prev:SetPoint("LEFT"); prev:SetLabel("<")
    local nxt = Skin.FlatButton(Core.f.btnRow, 46, 34, nav(1)); nxt:SetPoint("RIGHT"); nxt:SetLabel(">")
    Core.f.skip = Skin.FlatButton(Core.f.btnRow, Skin.INNER - 104, 34, Flow.Ignore); Core.f.skip:SetPoint("CENTER")
    if Core.f.skip.fs.SetFont then Core.f.skip.fs:SetFont(Skin.FONT, 10, ""); Core.f.skip.fs:SetTextColor(Skin.COL.gold[1], Skin.COL.gold[2], Skin.COL.gold[3]) end
    -- icone du role (passer, OK, revenir, retablir), devant le mot : voir SetSkip (Skin.lua)
    Core.f.skip.icon = Core.f.skip:CreateTexture(nil, "ARTWORK"); Core.f.skip.icon:SetSize(11, 11)
    Core.f.skip.icon:SetPoint("RIGHT", Core.f.skip.fs, "LEFT", -6, 0)
    if Core.f.skip.icon.SetVertexColor then Core.f.skip.icon:SetVertexColor(Skin.COL.gold[1], Skin.COL.gold[2], Skin.COL.gold[3]) end
    Core.f.skip.icon:Hide()
    for _, b in ipairs({ prev, nxt }) do
        if b.fs.SetFont then b.fs:SetFont(Skin.FONT, 13, ""); b.fs:SetTextColor(Skin.COL.accent[1], Skin.COL.accent[2], Skin.COL.accent[3]) end
        b:SetLabel(b == prev and "<" or ">")
    end
    for _, b in ipairs({ prev, nxt }) do
        if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    end
    -- infobulles des boutons
    for _, bt in ipairs({ { prev, "btnPrevTip" }, { nxt, "btnNextTip" }, { Core.f.skip, "btnOkTip" } }) do
        bt[1]:HookScript("OnEnter", function(self)
            Skin.Tip():SetOwner(self, "ANCHOR_BOTTOM"); Skin.Tip():AddLine(Core.T(bt[2]), 1, 1, 1, true); Skin.Tip():Show()
        end)
        bt[1]:HookScript("OnLeave", function() Skin.Tip():Hide() end)
    end

    Core.f.up = {}
    for k = 1, 4 do
        local b = CreateFrame("Button", nil, Core.f)
        b:SetSize(Skin.INNER, 26)
        local sep = Skin.Tex(b, Skin.COL.faint, 1, "ARTWORK"); sep:SetHeight(1); sep:SetPoint("TOPLEFT"); sep:SetPoint("TOPRIGHT")
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(14, 14); b.icon:SetPoint("LEFT", 2, -1)
        b.right = Skin.FS(b, 11, Skin.COL.gold, Skin.FONT, "RIGHT"); b.right:SetPoint("RIGHT", 0, -1)
        local fs = Skin.FS(b, 11, Skin.COL.soft, Skin.FONT, "LEFT")
        fs:SetPoint("LEFT", 22, -1); fs:SetPoint("RIGHT", b.right, "LEFT", -6, 0)
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        b.fs = fs
        local h = Skin.Tex(b, Skin.COL.accent, 0.08, "HIGHLIGHT"); h:SetAllPoints()
        b:SetScript("OnClick", function(self)
            if self.idx then State.focus = self.idx; State.peek = nil; State.lastWP = nil; Skin.Refresh(true) end
        end)
        b:SetScript("OnEnter", function(self)
            Skin.Tip():SetOwner(self, "ANCHOR_LEFT")
            Skin.Tip():AddLine(Core.T("clickGo"))
            local st = self.idx and State.steps and State.steps[self.idx]
            if st and st.t == "do" and type(st.id) == "number" and Est.EST[st.id] then
                local e = Est.Estimate({ st.id }, false)
                Skin.Tip():AddLine(Core.T("estTip", Est.FormatNum(e.xp), Est.FormatNum(e.qxp), Est.FormatNum(e.mxp), math.max(1, math.floor(e.secs / 60 + 0.5)), Est.FormatNum(e.perHour)), 0.8, 0.73, 0.56, true)
            end
            Skin.Tip():Show()
        end)
        b:SetScript("OnLeave", function() Skin.Tip():Hide() end)
        b:Hide()
        Core.f.up[k] = b
    end

    Core.f.passed = Skin.FS(Core.f, 10, Skin.COL.gold, Skin.FONT, "LEFT"); Core.f.passed:SetWidth(Skin.INNER - 22); Core.f.passed:Hide()
    Core.f.badge.lbl:SetText(Core.T("lvlShort"))

    -- v1.40 : poignee en bas a droite = agrandir / reduire la fenetre (echelle, comme dans les options), hors combat.
    -- v1.41 : la meme poignee existe sur le mode compact. Les deux fenetres ont la meme largeur et partagent leur
    -- coin : on garde fixe le coin haut-gauche de la fenetre visible (src) et on change l'echelle des deux.
    local function makeGrip(src)
        local grip = CreateFrame("Button", nil, src)
        grip:SetSize(12, 12); grip:SetPoint("BOTTOMRIGHT", -1, 1)
        if grip.SetFrameLevel and src.GetFrameLevel then grip:SetFrameLevel((src:GetFrameLevel() or 1) + 10) end
        local gt = grip:CreateTexture(nil, "OVERLAY"); gt:SetAllPoints()
        gt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        if gt.SetVertexColor then gt:SetVertexColor(Skin.COL.accent[1], Skin.COL.accent[2], Skin.COL.accent[3]) end
        local gh = grip:CreateTexture(nil, "HIGHLIGHT"); gh:SetAllPoints(); gh:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        grip:SetScript("OnMouseDown", function(self)
            if State.DB.locked or (InCombatLockdown and InCombatLockdown()) or not GetCursorPosition then return end
            local s, left, top = src:GetScale() or 1, src:GetLeft(), src:GetTop()
            if not (left and top) then return end
            local ui = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            -- le coin haut-gauche reste en place ; la largeur suit la souris
            self.drag = { s = s, left = left * s, top = top * s, x0 = GetCursorPosition() / ui, w = Skin.W * s, ui = ui }
            self:SetScript("OnUpdate", function()
                local d = self.drag; if not d then return end
                local dx = GetCursorPosition() / d.ui - d.x0
                local sc = math.max(0.6, math.min(1.5, d.s * (d.w + dx) / d.w))
                Core.f:SetScale(sc); Core.f:ClearAllPoints(); Core.f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", d.left / sc, d.top / sc)
                local mf = rawget(Core.f, "mini"); if mf and mf.SetScale then mf:SetScale(sc) end
            end)
        end)
        grip:SetScript("OnMouseUp", function(self)
            self:SetScript("OnUpdate", nil)
            if not self.drag then return end
            self.drag = nil
            State.DB.scale = math.floor((Core.f:GetScale() or 1) * 100 + 0.5) / 100
            SaveWinPos()
            local mf = rawget(Core.f, "mini"); if mf and mf.SetScale then mf:SetScale(State.DB.scale) end
            if ns.UI and ns.UI.RefreshOptions then ns.UI.RefreshOptions() end
        end)
        grip:SetScript("OnEnter", function(self) Skin.Tip():SetOwner(self, "ANCHOR_RIGHT"); Skin.Tip():AddLine(Core.T("winResize"), 1, 1, 1, true); Skin.Tip():Show() end)
        grip:SetScript("OnLeave", function() Skin.Tip():Hide() end)
        return grip
    end
    Core.f.grip = makeGrip(Core.f)

    -- bouton « - » en haut a droite : passer en mode compact
    local function miniBtn(parent, label, tipKey)
        local b = CreateFrame("Button", nil, parent); b:SetSize(16, 14)
        b.fs = Skin.FS(b, 12, Skin.COL.gold, Skin.FONT, "CENTER"); b.fs:SetPoint("CENTER")
        b.fs:SetText(Skin.Glyph(b, label, Skin.COL.gold) and "" or label)   -- v1.42 : signe dessine, bien centre
        local h = Skin.Tex(b, Skin.COL.accent, 0.12, "HIGHLIGHT"); h:SetAllPoints()
        b:SetScript("OnClick", function()
            -- v1.52 (demande de l'auteur) : Maj + clic sur le « - » = replier / deplier toutes les parties d'un coup
            if tipKey == "miniEnter" and IsShiftKeyDown and IsShiftKeyDown() then
                local fold = not (State.DB.upHidden and State.DB.detailsHidden and not State.DB.aroundOpen)
                State.DB.upHidden = fold or nil; State.DB.detailsHidden = fold or nil; State.DB.aroundOpen = (not fold) or nil
                Skin.Refresh()
                return
            end
            ToggleMini()
        end)
        b:SetScript("OnEnter", function(self)
            Skin.Tip():SetOwner(self, "ANCHOR_LEFT"); Skin.Tip():AddLine(Core.T(tipKey), 1, 1, 1, true)
            if tipKey == "miniEnter" then Skin.Tip():AddLine(Core.T("miniShiftTip"), 0.66, 0.60, 0.48, true) end
            Skin.Tip():Show()
        end)
        b:SetScript("OnLeave", function() Skin.Tip():Hide() end)
        return b
    end
    Core.f.miniBtn = miniBtn(Core.f, "-", "miniEnter"); Core.f.miniBtn:SetPoint("RIGHT", Core.f, "TOPRIGHT", -6, -Window.HEAD_H / 2)
    -- bouton « Intendance » : icone sac de courses (Media/IcoShop, choisie par l'auteur sur maquette) a gauche
    -- du « - », en capitale seulement (affiche/cache par Layout ; infobulle au survol)
    Core.f.qmBtn = CreateFrame("Button", nil, Core.f); Core.f.qmBtn:SetSize(16, 16)
    Core.f.qmBtn:SetPoint("RIGHT", Core.f.miniBtn, "LEFT", -2, 0)
    Skin.Border(Core.f.qmBtn, Skin.COL.accent, 0.6)
    Core.f.qmBtn.icon = Core.f.qmBtn:CreateTexture(nil, "ARTWORK"); Core.f.qmBtn.icon:SetSize(14, 14); Core.f.qmBtn.icon:SetPoint("CENTER")
    Core.f.qmBtn.icon:SetTexture("Interface\\AddOns\\" .. (ADDON or "OghoulesWarpath") .. "\\Media\\IcoShop")
    if Core.f.qmBtn.icon.SetVertexColor then Core.f.qmBtn.icon:SetVertexColor(Skin.COL.accent[1], Skin.COL.accent[2], Skin.COL.accent[3]) end
    local qh = Skin.Tex(Core.f.qmBtn, Skin.COL.accent, 0.15, "HIGHLIGHT"); qh:SetAllPoints()
    Core.f.qmBtn:SetScript("OnClick", function() if Quartermaster.QMOpen then Quartermaster.QMOpen() end end)
    Core.f.qmBtn:SetScript("OnEnter", function(self) Skin.Tip():SetOwner(self, "ANCHOR_LEFT"); Skin.Tip():AddLine(Core.T("qmTitle")); Skin.Tip():AddLine(Core.T("qmBtnTip"), 1, 1, 1, true); Skin.Tip():Show() end)
    Core.f.qmBtn:SetScript("OnLeave", function() Skin.Tip():Hide() end)
    Core.f.qmBtn:Hide()
    -- v1.41 (audit) : « ? » = les gestes caches, affiches par-dessus la fenetre (un clic referme)
    Core.f.helpBtn = CreateFrame("Button", nil, Core.f); Core.f.helpBtn:SetSize(16, 16)
    Core.f.helpBtn:SetPoint("RIGHT", Core.f.miniBtn, "LEFT", -2, 0)
    Skin.Border(Core.f.helpBtn, Skin.COL.accent, 0.6)
    Core.f.helpBtn.fs = Skin.FS(Core.f.helpBtn, 11, Skin.COL.accent, Skin.FONT, "CENTER"); Core.f.helpBtn.fs:SetPoint("CENTER", 0, 0); Core.f.helpBtn.fs:SetText("?")
    local hph = Skin.Tex(Core.f.helpBtn, Skin.COL.accent, 0.15, "HIGHLIGHT"); hph:SetAllPoints()
    Core.f.helpOver = CreateFrame("Button", nil, Core.f)
    Core.f.helpOver:SetPoint("TOPLEFT", 1, -Window.HEAD_H - 1); Core.f.helpOver:SetPoint("BOTTOMRIGHT", -1, 1)
    if Core.f.helpOver.SetFrameLevel and Core.f.GetFrameLevel then Core.f.helpOver:SetFrameLevel((Core.f:GetFrameLevel() or 1) + 30) end
    local hob = Skin.Tex(Core.f.helpOver, Skin.COL.bg, 0.97, "BACKGROUND"); hob:SetAllPoints()
    Core.f.helpOver.head = Skin.FS(Core.f.helpOver, 10, Skin.COL.gold, Skin.FONT, "LEFT"); Core.f.helpOver.head:SetPoint("TOPLEFT", Skin.PAD, -14)
    Core.f.helpOver.fs = Skin.FS(Core.f.helpOver, 11, Skin.COL.soft, Skin.FONT, "LEFT"); Core.f.helpOver.fs:SetPoint("TOPLEFT", Core.f.helpOver.head, "BOTTOMLEFT", 0, -10)
    Core.f.helpOver.fs:SetWidth(Skin.INNER)
    if Core.f.helpOver.fs.SetWordWrap then Core.f.helpOver.fs:SetWordWrap(true) end
    if Core.f.helpOver.fs.SetSpacing then Core.f.helpOver.fs:SetSpacing(5) end
    Core.f.helpOver:SetScript("OnClick", function(self) self:Hide() end)
    -- v1.43 : les options aussi (ou les trouver + un bouton pour les ouvrir)
    Core.f.helpOver.opts = Skin.FlatButton(Core.f.helpOver, Skin.INNER, 24, function()
        Core.f.helpOver:Hide()
        if SlashCmdList and SlashCmdList.WARPATH then SlashCmdList.WARPATH("options") end
    end)
    Core.f.helpOver.opts:SetPoint("BOTTOM", Core.f.helpOver, "BOTTOM", 0, 12)
    if Core.f.helpOver.opts.fs then Core.f.helpOver.opts.fs:SetTextColor(Skin.COL.accent[1], Skin.COL.accent[2], Skin.COL.accent[3]) end
    Core.f.helpOver:Hide()
    Core.f.helpBtn:SetScript("OnClick", function()
        if Core.f.helpOver:IsShown() then Core.f.helpOver:Hide(); return end
        Core.f.helpOver.head:SetText(Skin.Caps(Core.T("helpHead")))
        local L = {}
        for k = 1, 10 do L[#L + 1] = "|cffccba8f" .. Core.T("helpK" .. k) .. "|r  " .. Core.T("helpV" .. k) end
        Core.f.helpOver.fs:SetText(table.concat(L, "\n"))
        Core.f.helpOver.opts:SetLabel(Skin.Caps(Core.T("helpOpts")))
        Core.f.helpOver:Show()
    end)
    Core.f.helpBtn:SetScript("OnEnter", function(self) Skin.Tip():SetOwner(self, "ANCHOR_LEFT"); Skin.Tip():AddLine(Core.T("helpHead")); Skin.Tip():Show() end)
    Core.f.helpBtn:SetScript("OnLeave", function() Skin.Tip():Hide() end)
    -- v1.46 (retour d'un joueur : il cherchait la taille de la fenetre) : engrenage a gauche du « ? »,
    -- ouvre les options sur l'onglet Apparence (taille de la fenetre et de la fleche)
    Core.f.optBtn = CreateFrame("Button", nil, Core.f); Core.f.optBtn:SetSize(16, 16)
    Core.f.optBtn:SetPoint("RIGHT", Core.f.helpBtn, "LEFT", -2, 0)
    Skin.Border(Core.f.optBtn, Skin.COL.accent, 0.6)
    Core.f.optBtn.icon = Core.f.optBtn:CreateTexture(nil, "ARTWORK"); Core.f.optBtn.icon:SetSize(12, 12); Core.f.optBtn.icon:SetPoint("CENTER")
    Core.f.optBtn.icon:SetTexture("Interface\\AddOns\\" .. (ADDON or "OghoulesWarpath") .. "\\Media\\IcoGear")
    if Core.f.optBtn.icon.SetVertexColor then Core.f.optBtn.icon:SetVertexColor(Skin.COL.accent[1], Skin.COL.accent[2], Skin.COL.accent[3]) end
    local oh = Skin.Tex(Core.f.optBtn, Skin.COL.accent, 0.15, "HIGHLIGHT"); oh:SetAllPoints()
    Core.f.optBtn:SetScript("OnClick", function() if ns.UI and ns.UI.OpenOptionsTab then ns.UI.OpenOptionsTab(6) end end)
    Core.f.optBtn:SetScript("OnEnter", function(self) Skin.Tip():SetOwner(self, "ANCHOR_LEFT"); Skin.Tip():AddLine(Core.T("optBtn")); Skin.Tip():AddLine(Core.T("optBtnTip"), 1, 1, 1, true); Skin.Tip():Show() end)
    Core.f.optBtn:SetScript("OnLeave", function() Skin.Tip():Hide() end)

    -- v1.40 : mode compact = une petite fenetre a part, seulement les objectifs (ou une ligne pour prendre/rendre)
    local mf = CreateFrame("Frame", "WarpathMini", UIParent)
    mf:SetSize(MINI_W, 30)
    -- v1.41 : collee au coin haut-droit de la grande fenetre (le « - » et le « + » au meme endroit) ;
    -- la deplacer deplace la grande fenetre (une seule position, DB.wpos)
    State.DB.mpos = nil
    mf:SetPoint("TOPRIGHT", Core.f, "TOPRIGHT")
    local mbg = Skin.Tex(mf, Skin.COL.bg, 0.90, "BACKGROUND"); mbg:SetAllPoints()
    Skin.Border(mf, Skin.COL.line, 0.8, "BORDER")
    mf:SetClampedToScreen(true); mf:SetMovable(true); mf:EnableMouse(true); mf:RegisterForDrag("LeftButton")
    mf:SetScript("OnDragStart", function(self) if not State.DB.locked then self:StartMoving() end end)
    mf:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local r, t = self:GetRight(), self:GetTop()
        if r and t then
            local k = (self.GetEffectiveScale and Core.f.GetEffectiveScale) and (self:GetEffectiveScale() / Core.f:GetEffectiveScale()) or 1
            Core.f:ClearAllPoints(); Core.f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", r * k, t * k)
            SaveWinPos()
        end
        self:ClearAllPoints(); self:SetPoint("TOPRIGHT", Core.f, "TOPRIGHT")
    end)
    -- en-tete comme la grande fenetre (meme hauteur, losange rouge) : le « + » tombe exactement a la place du « - »
    local mhb = Skin.Tex(mf, Skin.COL.panel or Skin.COL.bg, 1, "BORDER"); mhb:SetHeight(Window.HEAD_H); mhb:SetPoint("TOPLEFT", 1, -1); mhb:SetPoint("TOPRIGHT", -1, -1)
    local mhl = Skin.Tex(mf, Skin.COL.line, 1, "ARTWORK"); mhl:SetHeight(1); mhl:SetPoint("TOPLEFT", 0, -Window.HEAD_H); mhl:SetPoint("TOPRIGHT", 0, -Window.HEAD_H)
    mf.gem = Skin.Diamond(mf, 8, Skin.COL.red); mf.gem:SetPoint("LEFT", mf, "TOPLEFT", Skin.PAD - 4, -Window.HEAD_H / 2)
    mf.plus = miniBtn(mf, "+", "miniExit"); mf.plus:SetPoint("RIGHT", mf, "TOPRIGHT", -6, -Window.HEAD_H / 2)
    mf.title = Skin.FS(mf, 12, Skin.COL.white, Skin.FONT, "LEFT"); mf.title:SetPoint("LEFT", mf, "TOPLEFT", Skin.PAD + 12, -Window.HEAD_H / 2)
    mf.title:SetPoint("RIGHT", mf, "TOPRIGHT", -28, -Window.HEAD_H / 2)
    if mf.title.SetWordWrap then mf.title:SetWordWrap(false) end
    -- titre = nom de la quete : clic = journal de quetes (comme le titre de la grande fenetre) ; glisser = deplacer
    mf.hit = CreateFrame("Button", nil, mf); mf.hit:SetPoint("TOPLEFT", 0, 0); mf.hit:SetPoint("BOTTOMRIGHT", mf, "TOPRIGHT", -26, -Window.HEAD_H)
    mf.hit.hl = Skin.Tex(mf.hit, Skin.COL.accent, 0.06, "HIGHLIGHT"); mf.hit.hl:SetAllPoints()
    if mf.hit.RegisterForDrag then mf.hit:RegisterForDrag("LeftButton") end
    mf.hit:SetScript("OnDragStart", function() local fn = mf:GetScript("OnDragStart"); if fn then fn(mf) end end)
    mf.hit:SetScript("OnDragStop", function() local fn = mf:GetScript("OnDragStop"); if fn then fn(mf) end end)
    mf.hit:SetScript("OnClick", function() if mf.questClick and Flow.OpenStepQuest then Flow.OpenStepQuest() end end)
    mf.hit:SetScript("OnEnter", function(self)
        if not mf.questClick then return end
        Skin.Tip():SetOwner(self, "ANCHOR_LEFT"); Skin.Tip():AddLine(mf.title:GetText() or ""); Skin.Tip():AddLine(Core.T("qtitleClick"), 0.66, 0.60, 0.48, true); Skin.Tip():Show()
    end)
    mf.hit:SetScript("OnLeave", function() Skin.Tip():Hide() end)
    mf.rows = {}
    mf.grip = makeGrip(mf)   -- v1.41 : redimensionner aussi en mode compact
    if mf.SetScale then mf:SetScale(State.DB.scale or 1) end
    mf:Hide()
    Core.f.mini = mf

    Core.f:SetShown(State.DB.shown ~= false)
    if Core.f.SetScale then Core.f:SetScale(State.DB.scale or 1) end
end

------------------------------------------------------------------
-- Mode compact (v1.40) : la grande fenetre est cachee, la petite montre l'essentiel de l'etape
------------------------------------------------------------------
-- v1.41 : meme largeur que la grande fenetre, memes marges (demande de l'auteur)
MINI_W, MINI_PAD = Skin.W, Skin.PAD
local function miniRow(mf, k)
    local r = mf.rows[k]
    if r then return r end
    r = CreateFrame("Frame", nil, mf); r:SetSize(MINI_W - 2 * MINI_PAD, 16)
    r.gem = Skin.Diamond(r, 7, Skin.COL.accent, true); r.gem:SetPoint("LEFT", -2, 0)
    r.count = Skin.FS(r, 12, Skin.COL.accent, Skin.FONT, "RIGHT"); r.count:SetPoint("RIGHT")
    r.name = Skin.FS(r, 12, Skin.COL.white, Skin.FONT, "LEFT"); r.name:SetPoint("LEFT", 14, 0); r.name:SetPoint("RIGHT", r.count, "LEFT", -8, 0)
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    mf.rows[k] = r
    return r
end

function Window.UpdateMini()
    local mf = Core.f and rawget(Core.f, "mini")
    if not mf then return end
    local dl = Flow.DungeonLogActive()
    local shown = State.DB.shown ~= false
    -- Intendance (v1.41) : l'ecran de choix, ou la tournee (sauf en mode compact : une ligne)
    local qs = Quartermaster.QMPanelState and Quartermaster.QMPanelState() or nil
    local qpanel = qs and shown and not dl and (qs == "pick" or not State.DB.mini) and qs or nil
    -- v1.41 : le mode compact marche aussi dans le journal de donjon (les quetes du donjon et leur progression)
    local on = State.DB.mini and shown and State.steps and not qpanel and true or false
    Core.f:SetShown(shown and not on and not qpanel)
    mf:SetShown(on)
    if Quartermaster.QMShowPanel then Quartermaster.QMShowPanel(qpanel) end
    if not on then return end
    local lines = {}
    local qs2, qk, qn = nil, nil, nil
    if qs == "tour" and Quartermaster.QMCurrent then qs2, qk, qn = Quartermaster.QMCurrent() end
    if qs2 then lines[1] = { verb = Skin.Caps(Core.T("qmStopN", qk, qn)), text = qs2.label } end
    -- journal de donjon : une ligne par quete prise, compteur a droite (coche quand c'est fini)
    if dl and not qs2 then
        for _, r in ipairs(Flow.DungeonLogList()) do
            if not r.later then
                local cnt = (r.prog or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                lines[#lines + 1] = { text = r.name or "", count = cnt, done = r.done }
            end
        end
        if #lines == 0 then lines[1] = { verb = Skin.Caps(Core.T("dgLog")), text = Core.Title and State.G and Core.Title(State.G) or "" } end
    end
    -- objectifs de l'etape (ceux de la grande fenetre), sinon une ligne : type d'etape + PNJ ou lieu
    for k = 1, ((qs2 or dl) and 0 or rawget(Core.f, "nObj") or 0) do
        local w = Core.f.obj[k]
        if w and w.kind == "obj" then lines[#lines + 1] = { text = w.name:GetText() or "", count = w.count:GetText() or "", done = w.done } end
    end
    if #lines == 0 then
        local s = State.steps[State.peek or State.focus or State.current]
        if s then
            local nm = (s.t ~= "do" and Core.f.dest and Core.f.dest:IsShown() and Core.f.destName:GetText()) or (s.t ~= "do" and s.quest and Core.QName(s)) or ""
            if nm == "" and Core.StepText then nm = (Core.StepText(s) or ""):gsub("\n.*", "") end
            -- v1.52 (audit G) : detour ou etape « Donjon » : le meme en-tete que la grande fenetre
            local mv = rawget(Core.f, "miniVerb")
            lines[1] = { verb = Skin.Caps(mv or Core.T(s.t)), text = nm }
        end
    end
    -- en-tete : nom de la quete (cliquable), sinon Intendance / donjon / guide
    local head, click = nil, false
    if qs2 then head = Core.T("qmTitle")
    elseif dl then head = Core.Title and State.G and Core.Title(State.G) or ""
    else
        local s = State.steps[State.peek or State.focus or State.current]
        local qn = s and s.quest and Core.QName(s)
        local mh = rawget(Core.f, "miniHead")
        if type(mh) == "string" and mh ~= "" then head = mh
        elseif qn and qn ~= "" then head = qn:match("^(.-) %+ ") or qn; click = true
        else head = Core.Title and State.G and Core.Title(State.G) or "" end
    end
    head = (head or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    mf.questClick = click
    mf.title:SetText(Skin.Caps(head))
    local sw = (mf.title.GetUnboundedStringWidth and mf.title:GetUnboundedStringWidth()) or (mf.title.GetStringWidth and mf.title:GetStringWidth())
    local aw = mf.title.GetWidth and mf.title:GetWidth()
    if type(sw) == "number" and type(aw) == "number" and aw > 0 and sw > aw then mf.title:SetText(Core.Upper(head)) end
    local y = -Window.HEAD_H - 12
    for k, l in ipairs(lines) do
        if k > 8 then break end
        local r = miniRow(mf, k)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", mf, "TOPLEFT", MINI_PAD, y)
        r.name:SetText(l.verb and ("|cffd6b866" .. l.verb .. "|r  " .. l.text) or l.text)
        r.count:SetText(l.count or "")
        local c = l.done and Skin.COL.dim or Skin.COL.white
        if r.name.SetTextColor then r.name:SetTextColor(c[1], c[2], c[3]) end
        c = l.done and Skin.COL.dim or Skin.COL.accent
        if r.count.SetTextColor then r.count:SetTextColor(c[1], c[2], c[3]) end
        r.gem:SetStyle(l.done and Skin.COL.dim or Skin.COL.accent, not l.done)
        -- ligne unique (note, prise, remise) : le texte peut passer a la ligne ; objectifs : une ligne chacun
        if r.name.SetWordWrap then r.name:SetWordWrap(l.verb and true or false) end
        local h = 16
        if l.verb and r.name.GetStringHeight then
            local sh = r.name:GetStringHeight()
            if type(sh) == "number" and sh > h then h = math.min(sh, 60) end
        end
        r:SetHeight(h)
        r:Show()
        y = y - h - 4
    end
    for k = #lines + 1, #mf.rows do mf.rows[k]:Hide() end
    mf:SetHeight(-y + 14)   -- (place pour la poignee en bas a droite)
end

function ToggleMini()
    State.DB.mini = not State.DB.mini
    Skin.Refresh(true)
end

-- afficher / cacher le guide (grande ou petite fenetre selon le mode)
function ShowGuide(v)
    State.DB.shown = v and true or false
    if Core.f then
        if Window.UpdateMini then pcall(Window.UpdateMini) end
        if not rawget(Core.f, "mini") then Core.f:SetShown(State.DB.shown) end
    end
    if ns.Targets then ns.Targets.Refresh() end
end

------------------------------------------------------------------
-- Ce que la fenetre d'options (Options.lua) utilise du moteur
------------------------------------------------------------------
ns.E = {
    T = Core.T, Title = Core.Title, Lang = Core.Lang, say = Core.say, Refresh = Skin.Refresh, SetGuide = Flow.SetGuide,
    StartDungeon = Flow.StartDungeon, StopDungeon = Flow.StopDungeon, ClearWaypoint = Route.ClearWaypoint,
    AutoPick = Flow.AutoPick, AllDone = Flow.AllDone,
    ClassQuestList = function() return Flow.ClassQuestList() end, DungeonLeft = function(k) return Flow.DungeonLeft(k) end,PlaceWaypointAgain = function() if State.steps and State.current and State.steps[State.current] then pcall(Route.SetWaypoint, State.steps[State.current]) end end, StyleGet = function() return Style.StyleGet() end,
    ApplyPreset = function(n) local ok, err = pcall(Style.ApplyPreset, n); if not ok then Core.say(Core.T("errInternal", tostring(err)), "error") end end, StyleChanged = function() Style.StyleReset(); local ok, err = pcall(Flow.Advance); if not ok then Core.say(Core.T("errInternal", tostring(err)), "error") end; Skin.Refresh(true) end, AskClass = function(q) Flow.AskChain(q, true) end, ChronShow = function(k) Chronicle.ChronShow(k) end, BugWindow = function() Commands.BugWindow() end,
    Guides = Core.Guides, ICON = Core.ICON, VERSION = Core.VERSION, CHECK = Core.CHECK,
    MAIN_ORDER = Core.MAIN_ORDER, IS_DUNGEON = Core.IS_DUNGEON, DUNGEONS = Core.DUNGEONS, MINLVL = Core.MINLVL, MAXLVL = Core.MAXLVL,
    DB = function() return State.DB end,
    Frame = function() return Core.f end,
    Guide = function() return State.G end,
    Steps = function() return State.steps end,
    Current = function() return State.current end,
    Race = function() return State.myRace end,
    ResetWP = function() State.lastWP = nil end,
    ShowGuide = function(v) ShowGuide(v) end,
    WarpathName = Skin.WarpathName,
    Tip = function() return Skin.Tip() end, GuideStatus = function(k) return Flow.GuideStatus(k) end,
    ProfOrder = function() return Profs.PROF_ORDER end, ProfKey = function(id) return Profs.PROF_KEY[id] end, ProfName = function(id) return Profs.ProfName(id) end, TrainerPins = function() if Profs.TrainerPinsRefresh then pcall(Profs.TrainerPinsRefresh, true) end end,
    ProfQuestList = function() return Profs.ProfQuestList() end, ProfOn = function(id) return Profs.ProfOn(id) end,
    ProfDetect = function() return Profs.ProfDetect(true) end,
    AskProf = function(q) Flow.AskChain(q, true, "prof") end,
    -- v1.52 : quetes speciales (Features/Special.lua, charge apres ce fichier)
    SpecialList = function() return ns.Mod.Special.List and ns.Mod.Special.List() or {} end,
    AskSpecial = function(k) if ns.Mod.Special.Ask then ns.Mod.Special.Ask(k, true) end end,
    -- v1.46 : fiche de donjon (Features/DungeonSheet.lua, charge apres ce fichier)
    DungeonName = function(d) return Flow.DungeonName(d) end,
    DungeonIdeal = function(k) return Flow.DungeonIdeal and Flow.DungeonIdeal(k) end,   -- v1.47 : n'est plus dans _G (DECL)
    DungeonSheetOpen = function(k) return DungeonSheet.DungeonSheetOpen and DungeonSheet.DungeonSheetOpen(k) end,
    DungeonBadge = function(k) if DungeonSheet.DungeonBadge then return DungeonSheet.DungeonBadge(k) end; return 0, 0 end,
    Kit = { COL = Skin.COL, FONT = Skin.FONT, DISPLAY = Skin.DISPLAY, Caps = Skin.Caps, Upper = Core.Upper, Spaced = Skin.Spaced, FS = Skin.FS, Tex = Skin.Tex,
            Diamond = Skin.Diamond, Divider = Skin.Divider, TitledRule = Skin.TitledRule, FlatButton = Skin.FlatButton,
            Border = Skin.Border, SectionHead = Skin.SectionHead, Chip = Skin.Chip, DiamondCheck = Skin.DiamondCheck,
            HeadButton = Skin.HeadButton, ScaleGrip = Skin.ScaleGrip, GoldFrame = Skin.GoldFrame },
}
ns.UI = ns.UI or {}

------------------------------------------------------------------
-- Carte de vol : apprendre les trajets connus et surligner la destination
------------------------------------------------------------------
taxiGlow = nil

function NodeKeyFor(name)
    if not name then return nil end
    for _, n in ipairs(Route.FLIGHTS) do
        if name:find(n.key, 1, true) then return n.key end
    end
end

function OnTaxiOpened()
    if not NumTaxiNodes then return end
    State.DB.fp = State.DB.fp or {}
    State.DB.fpLinks = State.DB.fpLinks or {}
    local target, here
    local reach = {}
    for i = 1, NumTaxiNodes() do
        local name = TaxiNodeName and TaxiNodeName(i)
        local kind = TaxiNodeGetType and TaxiNodeGetType(i)
        local key = NodeKeyFor(name)
        if key then
            -- CURRENT = ici ; REACHABLE = connu et atteignable. Sur Forever, DISTANT designe aussi les points
            -- JAMAIS decouverts (Everlook, Moonglade... au niveau 23) : on ne les compte plus (v1.39).
            if kind == "CURRENT" or kind == "REACHABLE" then State.DB.fp[key] = true end
            if kind == "CURRENT" then here = key; ns.Comfort.SetTaxiFrom(name) end
            if kind == "REACHABLE" then reach[key] = true end
        end
    end
    if here then
        State.DB.fpLinks[here] = reach
        -- Instantane des points connus a ce moment (voir CanFly, v1.43)
        local snap = {}
        for k in pairs(State.DB.fp) do snap[k] = true end
        State.DB.fpLinksKnown = State.DB.fpLinksKnown or {}
        State.DB.fpLinksKnown[here] = snap
        State.lastWP = nil
    end
    -- v1.45 : on recalcule le vol conseille APRES avoir lu la carte (points et liaisons a jour), puis on surligne.
    -- Avant : le surlignage (et le vol automatique) suivait l'ancien conseil, calcule sans les points que la carte
    -- venait de montrer (Ratchet -> Brackenwall au lieu de Camp Taurajo pour RFK, 2026-11-23).
    Skin.Refresh(true)
    if State.flightPlan then
        for i = 1, NumTaxiNodes() do
            local kind = TaxiNodeGetType and TaxiNodeGetType(i)
            if kind == "REACHABLE" and NodeKeyFor(TaxiNodeName and TaxiNodeName(i)) == State.flightPlan.to.key then target = i; break end
        end
    end
    if target then
        local btn = _G["TaxiButton" .. target]
        if btn then
            -- v1.47 (demande de l'auteur) : style Warpath au lieu du carre vert : losange dore autour du point,
            -- halo en losange qui grandit et s'efface (comme le repere de la carte du monde), etiquette en capitales
            if not taxiGlow then
                local G = "Interface\\AddOns\\" .. (ADDON or "OghoulesWarpath") .. "\\Media\\Gem"
                taxiGlow = CreateFrame("Frame", nil, UIParent)
                taxiGlow:SetSize(30, 30)
                taxiGlow:EnableMouse(false)
                -- melange additif : le losange eclaire le point du vol sans le cacher
                local halo = taxiGlow:CreateTexture(nil, "ARTWORK"); halo:SetPoint("CENTER"); halo:SetTexture(G)
                local gem = taxiGlow:CreateTexture(nil, "OVERLAY"); gem:SetAllPoints(); gem:SetTexture(G)
                if halo.SetBlendMode then halo:SetBlendMode("ADD"); gem:SetBlendMode("ADD") end
                gem:SetAlpha(0.6)
                taxiGlow.lbl = Skin.FS(taxiGlow, 10, Skin.COL.gold, Skin.FONT, "CENTER")
                taxiGlow.lbl:SetPoint("TOP", taxiGlow, "BOTTOM", 0, -2)
                local elapsed = 0
                taxiGlow:SetScript("OnUpdate", function(_, dt)
                    elapsed = (elapsed + (dt or 0)) % 1.6
                    local ph = elapsed / 1.6
                    local s = 30 * (1 + ph * 1.2)
                    halo:SetSize(s, s); halo:SetAlpha(0.8 * (1 - ph))
                end)
            end
            taxiGlow.lbl:SetText(Skin.Caps(Core.T("flyAdvised")))
            taxiGlow:SetParent(btn)
            taxiGlow:ClearAllPoints()
            taxiGlow:SetPoint("CENTER", btn, "CENTER")
            taxiGlow:SetFrameLevel((btn:GetFrameLevel() or 1) + 5)
            taxiGlow:Show()
        end
        Core.say(Core.T("flyTo", State.flightPlan.to.name))
        -- v1.45 : vol automatique retire (vol conseille faux, Ratchet -> Brackenwall). v1.47 (demande de l'auteur) :
        -- de retour en option a cocher (DB.flyAuto, decochee par defaut, nouvelle cle : l'ancienne autoFly etait
        -- cochee par defaut). Il suit le conseil recalcule ci-dessus. Garde-fous de la v1.41 : 0,4 s, carte encore
        -- ouverte, Maj = non, trajet calcule avant de decoller (vols avec escale) ; un blocage coupe l'option (Core.lua).
        if State.DB.flyAuto == true and not (IsShiftKeyDown and IsShiftKeyDown()) and TakeTaxiNode then
            local node = target
            local function go()
                if GetNumRoutes then pcall(GetNumRoutes, node) end
                ns.Trace("TakeTaxiNode"); TakeTaxiNode(node)
            end
            if C_Timer and C_Timer.After then C_Timer.After(0.4, function()
                local open = (TaxiFrame and TaxiFrame:IsShown()) or (not TaxiFrame and TaxiNodeName and TaxiNodeName(node))
                if open and State.DB.flyAuto == true and not (IsShiftKeyDown and IsShiftKeyDown()) then go() end
            end) else go() end
        end
    end
end

function OnTaxiClosed()
    if taxiGlow then taxiGlow:Hide() end
end

------------------------------------------------------------------
-- La fleche reste en place : si le jeu efface le waypoint a l'arrivee (ex. au maitre de vol),
-- on le remet des que tu t'en eloignes un peu, tant que le guide en a encore besoin.
------------------------------------------------------------------
-- v1.45 : le vol conseille n'etait recalcule qu'aux evenements (quete, zone, carte des vols), jamais en marchant :
-- arrive pres d'un maitre de vol, le conseil restait celui calcule plus loin. Toutes les 5 s, si tu as fait 100 m
-- depuis le dernier calcul (hors combat, hors vol), on rafraichit ; la fleche ne bouge que si le vol conseille change.
local flyCheck = { t = 0, pos = nil }
local function FlightRecheck()
    if not State.DB or State.DB.useFlights == false or State.peek then return end
    if (UnitOnTaxi and UnitOnTaxi("player")) or (InCombatLockdown and InCombatLockdown()) then return end
    local now = GetTime and GetTime() or 0
    if now - flyCheck.t < 5 then return end
    flyCheck.t = now
    local me = Route.PlayerWP()
    if not me then return end
    local p = flyCheck.pos
    if p and p[3] == me[3] and Route.Dist(p[1], p[2], me[1], me[2]) < 100 then return end
    flyCheck.pos = me
    if p then Skin.Refresh() end
end

wpTicker = CreateFrame("Frame")
wpElapsed = 0
distElapsed = 0
wpTicker:SetScript("OnUpdate", function(_, dt)
    distElapsed = distElapsed + (dt or 0)
    if distElapsed >= 0.5 then distElapsed = 0; Skin.UpdateDistance() end
    wpElapsed = wpElapsed + (dt or 0)
    if wpElapsed < 1 then return end
    wpElapsed = 0
    local m0 = Perf.PerfOn and Perf.PerfMem and Perf.PerfMem()                     -- v1.47 : /warpath perf
    local t0 = Perf.PerfOn and debugprofilestop and debugprofilestop()
    if State.DB then pcall(Route.LearnGates); pcall(FlightRecheck) end
    if t0 and Perf.PerfMark then Perf.PerfMark("Seconde : passages, fil, vols", debugprofilestop() - t0, m0 and (Perf.PerfMem() - m0)) end
    if not (State.DB and State.DB.wp and Route.desiredWP) then return end
    if not (C_Map and C_Map.HasUserWaypoint) or C_Map.HasUserWaypoint() then return end
    if UnitOnTaxi and UnitOnTaxi("player") then return end
    local me = Route.PlayerWP()
    local w = Route.WP(Route.desiredWP.m, Route.desiredWP.x, Route.desiredWP.y)
    local d = me and w and me[3] == w[3] and Route.Dist(me[1], me[2], w[1], w[2])
    if not d or d > 12 then Route.PlaceNative(Route.desiredWP) end
end)

-- v1.50 : ce que ce fichier offre aux autres (ns.Mod.Window)
do
    local M = ns.Mod.Window
    M.CreateUI = CreateUI
    M.OnTaxiClosed = OnTaxiClosed
    M.OnTaxiOpened = OnTaxiOpened
    M.ShowGuide = ShowGuide
    M.ToggleMini = ToggleMini
end
