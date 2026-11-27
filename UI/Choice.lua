-- Oghoule's Warpath : ecran de choix du parcours (UI/Choice.lua, v1.52, croquis de l'auteur)
-- Deux cartes : Bande de guerre (route "warband", donjons imbriques) / Eclaireur ("scout", classique).
-- Ouvert une fois par personnage tant que DB.routeChosen est vide (nouveaux et anciens personnages), puis par le
-- bouton des options ou /warpath parcours. Echap = Eclaireur (parcours par defaut), ne redemande plus.
-- Survol : l'image « fx » apparait en fondu, l'autre carte s'assombrit, un halo dore pulse derriere le cadre.
-- Images : celles de l'auteur (Media/Choix*.tga, HORS GIT : droits non publiables) si WarpathDropDB._artPerso
-- (/warpath art), sinon le fond Horde du jeu (fichier 2139059) teinte en rouge.
local ADDON, ns = ...
local State = ns.State
local Core = ns.Mod.Core -- v1.50 : module
local Skin = ns.Mod.Skin -- v1.50 : module
local Flow = ns.Mod.Flow -- v1.50 : module
-- v1.52 : module ns.Mod.Choice (publie en fin de fichier pour les autres fichiers)
local ShowChoice, MaybeShowChoice, SetRoute

local W, H, GAP = 300, 450, 44          -- carte 2:3
local GLOW = 26                          -- largeur du halo dore autour du cadre
local PULSE = 1.6                        -- secondes par battement du halo
local DIM, LIT = 0.65, 0.07              -- voile sur l'autre carte, eclat de la carte survolee
local GROW = 0.04                        -- la carte survolee grossit de 4 %
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local GAME_ART = 2139059                 -- interface/framegeneral/uiframehordebackground.blp
local GOLDC = { 0.85, 0.68, 0.32 }

local screen, cards, onDone

-- change de parcours ; tout est recalcule (rien n'est perdu). Aussi utilise par /warpath parcours.
function SetRoute(want, quiet)
    if not State.DB then return end
    State.DB.route = (want == "warband") and "warband" or nil
    State.DB.routeChosen = true
    if not quiet then
        local name = Core.T(want == "warband" and "routeWarband" or "routeScout")
        Core.say(Core.T("routeSet", name))
        Core.say(Core.T(want == "warband" and "routeWarbandTip" or "routeScoutTip"))
    end
    State.lastWP = nil
    if State.DB.guide and Core.Guides[State.DB.guide] then Flow.SetGuide(State.DB.guide, true) end
    Skin.Refresh(true)
end

local function artPerso() return WarpathDropDB and WarpathDropDB._artPerso end

-- halo : une seule image (Media/CardGlow, blanche, coins arrondis) teintee en dore, derriere la carte
local function Glow(c, parent)
    local g = parent:CreateTexture(nil, "BORDER")
    g:SetTexture(MEDIA .. "CardGlow"); g:SetVertexColor(GOLDC[1], GOLDC[2], GOLDC[3])
    g:SetPoint("TOPLEFT", c, "TOPLEFT", -GLOW, GLOW); g:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", GLOW, -GLOW)
    g:SetAlpha(0)
    return g
end

-- images (relu a chaque ouverture : /warpath art peut avoir change entre-temps)
local function SetArt(c)
    local name = c.key == "warband" and "ChoixWarband" or "ChoixScout"
    if artPerso() then
        c.art:SetTexture(MEDIA .. name); c.art:SetVertexColor(1, 1, 1); c.art:SetAlpha(1)
        c.fx:SetTexture(MEDIA .. name .. "Fx"); c.hasFx = true
        c.art:SetTexCoord(0, 1, 0, 0.75); c.fx:SetTexCoord(0, 1, 0, 0.75)   -- 512x768 en haut d'un 512x1024
    else
        c.art:SetTexture(GAME_ART); c.art:SetVertexColor(0.75, 0.35, 0.3); c.art:SetAlpha(0.55); c.art:SetTexCoord(0, 1, 0, 1)
        c.fx:SetTexture(nil); c.hasFx = false
    end
end
-- la carte grossit un peu (z de 0 a 1), sur place ; le texte est dans un cadre a part qui ne bouge pas
local function Grow(c, z)
    local s = 1 + GROW * z
    c:SetScale(s)
    c:ClearAllPoints(); c:SetPoint("CENTER", c:GetParent(), "CENTER", c.x / s, -10 / s)   -- l'echelle touche aussi le decalage
end

local function Card(parent, key, x)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(W, H); c:SetPoint("CENTER", parent, "CENTER", x, -10)
    c.key, c.x = key, x
    c.glow = Glow(c, parent)
    local base = Skin.Tex(c, { 0.24, 0.09, 0.08 }, 1, "BACKGROUND"); base:SetAllPoints()
    c.art = c:CreateTexture(nil, "ARTWORK", nil, 1); c.art:SetAllPoints()
    c.fx = c:CreateTexture(nil, "ARTWORK", nil, 2); c.fx:SetAllPoints(); c.fx:SetAlpha(0)
    -- eclaircit un peu la carte survolee
    c.lit = c:CreateTexture(nil, "ARTWORK", nil, 4); c.lit:SetAllPoints(); c.lit:SetColorTexture(1, 0.85, 0.7, 1)
    if c.lit.SetBlendMode then c.lit:SetBlendMode("ADD") end
    c.lit:SetAlpha(0)
    -- bas assombri pour le texte
    local shade = c:CreateTexture(nil, "ARTWORK", nil, 3)
    shade:SetColorTexture(1, 1, 1, 1)
    shade:SetPoint("BOTTOMLEFT"); shade:SetPoint("BOTTOMRIGHT"); shade:SetHeight(H * 0.45)
    if shade.SetGradient and CreateColor then
        shade:SetGradient("VERTICAL", CreateColor(0.04, 0.02, 0.02, 0.92), CreateColor(0.04, 0.02, 0.02, 0))
    else
        shade:SetColorTexture(0.04, 0.02, 0.02, 0.6)
    end
    -- voile qui assombrit la carte quand on survole l'autre
    c.veil = c:CreateTexture(nil, "OVERLAY", nil, 6); c.veil:SetAllPoints(); c.veil:SetColorTexture(0, 0, 0, 1); c.veil:SetAlpha(0)
    -- cadre dore
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = c:CreateTexture(nil, "OVERLAY", nil, 5); t:SetColorTexture(GOLDC[1], GOLDC[2], GOLDC[3], 1)
        if side == "TOP" or side == "BOTTOM" then t:SetHeight(3); t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
        else t:SetWidth(3); t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side) end
    end
    -- losange rouge accroche en haut : dans un cadre a part, au-dessus du cadre dore
    local top = CreateFrame("Frame", nil, c); top:SetSize(40, 40); top:SetPoint("CENTER", c, "TOP", 0, 0)
    top:SetFrameLevel(c:GetFrameLevel() + 5)
    local gem = top:CreateTexture(nil, "OVERLAY"); gem:SetAllPoints()
    gem:SetTexture(MEDIA .. "Gem"); gem:SetVertexColor(0.78, 0.22, 0.18)
    -- textes : cadre a part (pas d'echelle), au-dessus de la carte
    c.txt = CreateFrame("Frame", nil, parent); c.txt:SetSize(W, H); c.txt:SetPoint("CENTER", parent, "CENTER", x, -10)
    c.txt:SetFrameLevel(c:GetFrameLevel() + 8)
    c.title = Skin.FS(c.txt, 26, GOLDC, Skin.DISPLAY, "CENTER")
    c.title:SetPoint("BOTTOM", c.txt, "BOTTOM", 0, 118); c.title:SetText(Core.Upper(Core.T(key == "warband" and "routeWarband" or "routeScout")))
    c.desc = Skin.FS(c.txt, 12, Skin.COL.white, Skin.FONT, "CENTER")
    c.desc:SetPoint("TOP", c.title, "BOTTOM", 0, -14); c.desc:SetWidth(W - 44)
    c.desc:SetText(Core.T(key == "warband" and "choiceWarbandDesc" or "choiceScoutDesc"))
    c.hot = 0      -- 0 = repos, 1 = survole (anime)
    c:SetScript("OnEnter", function(self) self.want = 1; for _, o in ipairs(cards) do if o ~= self then o.dim = 1 end end end)
    c:SetScript("OnLeave", function(self) self.want = 0; for _, o in ipairs(cards) do o.dim = 0 end end)
    c:SetScript("OnClick", function(self)
        if self.chosen then return end
        for _, o in ipairs(cards) do o.chosen = true end
        for _, o in ipairs(cards) do if o ~= self then Skin.FadeOut(o, 0.35); Skin.FadeOut(o.txt, 0.35) end end
        SetRoute(self.key)
        if C_Timer and C_Timer.After then C_Timer.After(0.6, function() Skin.FadeOut(screen, 0.4) end) else screen:Hide() end
    end)
    return c
end

-- animations (fondu de l'image fx, voile, halo qui pulse, legere loupe)
local function Animate(_, el)
    local t = GetTime and GetTime() or 0
    for _, c in ipairs(cards) do
        local want = c.want or 0
        local step = (el or 0.03) / 0.2
        if c.hot < want then c.hot = math.min(want, c.hot + step) elseif c.hot > want then c.hot = math.max(want, c.hot - step) end
        local d = c.dimA or 0
        local dw = (c.dim or 0) * DIM
        if d < dw then d = math.min(dw, d + step * DIM) elseif d > dw then d = math.max(dw, d - step * DIM) end
        c.dimA = d
        if c.hasFx then c.fx:SetAlpha(c.hot) end
        c.veil:SetAlpha(d)
        c.lit:SetAlpha(LIT * c.hot)
        c.txt:SetAlpha(1 - 0.6 * d)
        local ph = (math.sin(t * 2 * math.pi / PULSE) + 1) / 2
        c.glow:SetAlpha(c.hot * (0.45 + 0.55 * ph))
        Grow(c, c.hot)
    end
end

local function Build()
    screen = CreateFrame("Frame", "WarpathChoice", UIParent)
    screen:SetAllPoints(UIParent); screen:SetFrameStrata("FULLSCREEN_DIALOG"); screen:EnableMouse(true)
    local bg = Skin.Tex(screen, { 0, 0, 0 }, 0.82, "BACKGROUND"); bg:SetAllPoints()
    cards = { Card(screen, "warband", -(W + GAP) / 2), Card(screen, "scout", (W + GAP) / 2) }
    local head = Skin.FS(screen, 13, GOLDC, Skin.FONT, "CENTER")
    head:SetPoint("BOTTOM", screen, "CENTER", 0, H / 2 + 34); head:SetText(Skin.Caps(Core.T("choiceHead")))
    local foot = Skin.FS(screen, 11, Skin.COL.soft, Skin.FONT, "CENTER")
    foot:SetPoint("TOP", screen, "CENTER", 0, -(H / 2) - 34); foot:SetText(Core.T("choiceFoot"))
    screen:SetScript("OnUpdate", Animate)
    -- Echap ferme : Eclaireur garde (parcours par defaut), on ne redemande plus
    screen:SetScript("OnHide", function()
        if State.DB and not State.DB.routeChosen then SetRoute("scout", true) end
        local f = onDone; onDone = nil
        if f then pcall(f) end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "WarpathChoice") end
    screen:Hide()
end

-- ouvre l'ecran ; done() est appele a la fermeture (ex. la bienvenue des nouveaux personnages)
function ShowChoice(done)
    if InCombatLockdown and InCombatLockdown() then if done then pcall(done) end; return end
    if not screen then Build() end
    onDone = done
    for _, c in ipairs(cards) do
        c.chosen = nil; c.want = 0; c.dim = 0; c.hot = 0; c.dimA = 0
        SetArt(c); Grow(c, 0)
        c:SetAlpha(1); c:Show(); c.txt:SetAlpha(1); c.txt:Show()
    end
    Skin.FadeIn(screen, 0.4)
end

-- une fois par personnage, tant qu'aucun parcours n'a ete choisi ; sinon done() tout de suite
function MaybeShowChoice(done)
    if State.DB and not State.DB.routeChosen then ShowChoice(done) elseif done then done() end
end

-- v1.52 : ce que ce fichier offre aux autres (ns.Mod.Choice)
do
    local M = ns.Mod.Choice
    M.ShowChoice = ShowChoice
    M.MaybeShowChoice = MaybeShowChoice
    M.SetRoute = SetRoute
end
