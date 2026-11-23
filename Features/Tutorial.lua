-- Oghoule's Warpath : visite guidee (Tutorial.lua) - pages de la visite, voir Core.lua
-- Ouverte depuis la fenetre de bienvenue (« Faire la visite ») ou avec /warpath tuto ; DB.tutoSeen = vue.
-- Uniquement des cadres ordinaires (aucun bouton securise) parentes a UIParent : la fenetre du guide
-- n'est jamais touchee (on la regarde a travers un « trou » dans le voile). Cache en combat, revient apres.
-- Ajouter une page = une entree dans PAGES : head/text (cles Locale), target (fonction -> cadre a montrer).
-- En bas : les astuces au bon moment (fleche, ciblage, pierre de foyer), une fois chacune (DB.tutoTips).
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end

-- Chaque target renvoie les morceaux de la grande fenetre a entourer (le trou = leur union).
-- Une page dont rien n'est affiche est sautee. La visite se fait toujours en mode complet.
local function Win() return rawget(_ENV, "f") or _G.WarpathFrame end
local function Shown(...)
    local out = {}
    for i = 1, select("#", ...) do
        local r = select(i, ...)
        if r and r.IsVisible and r:IsVisible() then out[#out + 1] = r end
    end
    return out
end

local PAGES = {
    { welcome = true, text = "tutoWelcome" },                                   -- accueil (carte centree, sans trou)
    -- v1.43 (demande de l'auteur) : de haut en bas, comme la fenetre (le trou descend sans sauter)
    { head = "tutoWinHead", text = "tutoWin", target = function() return Shown(Win()) end },
    { head = "tutoHeadHead", text = "tutoHead", header = true, target = function() return Shown(Win()) end },
    -- type + titre, destination, objectifs : l'un sous l'autre dans la fenetre, donc une seule page
    { head = "tutoStepHead", text = "tutoStep", target = function()
        local w = Win(); if not w then return {} end
        local t = Shown(w.kindRow, w.qtitle, w.dest, w.text)
        for _, row in ipairs(rawget(w, "obj") or {}) do if row:IsVisible() then t[#t + 1] = row end end
        return t
    end },
    { head = "tutoNextHead", text = "tutoNextUp", target = function()
        local w = Win(); if not w then return {} end
        local t = Shown(w.nextRule)
        for _, b in ipairs(rawget(w, "up") or {}) do if b:IsVisible() then t[#t + 1] = b end end
        return t
    end },
    { head = "tutoBtnHead", text = "tutoBtn", target = function() local w = Win(); return Shown(w and w.btnRow) end },
    -- v1.43 (demande de l'auteur) : la fleche = la partie la plus importante, juste apres la fenetre.
    -- Vue ici = l'astuce « fleche » ne viendra pas (elle sert de rattrapage si la fleche n'etait pas a l'ecran).
    { key = "arrow", head = "tutoArrowHead", text = "tutoArrow", target = function() return Shown(_G.WarpathArrow) end },
}

local overlay             -- voile plein ecran (nomme : Echap le ferme)
local pending = false     -- visite ouverte mais cachee par un combat
local tries = 0
local onDone              -- appele une fois la visite terminee (ex. : fin de la bienvenue)
local page = 1
local guideWasShown       -- le guide etait-il affiche avant la visite (on le remet comme avant)
local miniWas             -- le mode compact etait-il actif (visite en mode complet, puis on le remet)
local TipDelay            -- (astuces, definie plus bas) repousse la prochaine astuce

local function InCombat() return InCombatLockdown and InCombatLockdown() end
local function Finish() pending = false; if overlay then overlay:Hide() end end

-- trou dans le voile, en coordonnees du voile (gauche, bas, droite, haut) ; nil = voile plein
local function SetHole(l, b, r, t)
    local v = overlay.veil
    for _, x in ipairs(v) do x:ClearAllPoints() end
    if not l then
        v[1]:SetAllPoints(overlay)
        for i = 2, 4 do v[i]:Hide() end
        overlay.ring:Hide()
        return
    end
    for i = 2, 4 do v[i]:Show() end
    v[1]:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, t); v[1]:SetPoint("TOPRIGHT", overlay, "TOPRIGHT")       -- dessus
    v[2]:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT"); v[2]:SetPoint("TOPRIGHT", overlay, "BOTTOMRIGHT", 0, b)    -- dessous
    v[3]:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, b); v[3]:SetPoint("TOPRIGHT", overlay, "BOTTOMLEFT", l, t) -- gauche
    v[4]:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", r, b); v[4]:SetPoint("TOPRIGHT", overlay, "BOTTOMRIGHT", 0, t) -- droite
    local ring = overlay.ring
    ring:ClearAllPoints(); ring:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", l, b); ring:SetSize(r - l, t - b)
    ring:Show()
end

-- rectangle englobant des morceaux dans les coordonnees du voile (+ marge), ou nil si rien a l'ecran.
-- header = seulement la bande d'en-tete de la fenetre (HEAD_H).
local function RectOf(parts, pad, header)
    local w = Win()
    if not (parts and #parts > 0) then return nil end
    local ok, l, b, r, t = pcall(function()
        local os = overlay:GetEffectiveScale()
        local L, B, R, T
        for _, p in ipairs(parts) do
            -- echelle propre a chaque morceau (la fleche a la sienne) ; sinon celle de la fenetre
            local ps = (p.GetEffectiveScale and p:GetEffectiveScale()) or (w and w:GetEffectiveScale()) or os
            local s = ps / os
            local pl, pb, pr, pt = p:GetLeft(), p:GetBottom(), p:GetRight(), p:GetTop()
            if pl and pb and pr and pt then
                local top = pt * s
                if header then pb = pt - (HEAD_H or 34) end
                L = math.min(L or pl * s, pl * s); B = math.min(B or pb * s, pb * s)
                R = math.max(R or pr * s, pr * s); T = math.max(T or top, top)
            end
        end
        if not L then return nil end
        return L, B, R, T
    end)
    if not ok or not (l and b and r and t) then return nil end
    return l - pad, b - pad, r + pad, t + pad
end

-- une page a montrer ? (accueil toujours ; sinon il faut un morceau a l'ecran)
local function Usable(n)
    local p = PAGES[n]
    if not p then return false end
    if p.welcome then return true end
    local ok, parts = pcall(p.target)
    return ok and parts and #parts > 0 or false
end

local function Render()
    local p = PAGES[page]
    local card = overlay.card
    -- pages vraiment montrees (celles dont la zone est a l'ecran) : losanges et bouton « Terminer »
    local list, cur = {}, 1
    for i = 1, #PAGES do
        if i == page or Usable(i) then list[#list + 1] = i; if i == page then cur = #list end end
    end
    local last = cur == #list
    card:ClearAllPoints()
    if p.welcome then
        card:SetWidth(380)
        card.title:SetFont(DISPLAY, 16, ""); card.title:SetJustifyH("CENTER")
        card.title:SetText(Caps("Oghoule's Warpath"))
    else
        card:SetWidth(320)
        card.title:SetFont(FONT, 12, ""); card.title:SetJustifyH("CENTER")
        card.title:SetText(Caps(T(p.head)))
    end
    card.rule:SetWidth(card:GetWidth() - 60)
    card.text:SetWidth(card:GetWidth() - 50)
    card.text:SetText(T(p.text))
    -- losanges : un par page, la page courante pleine
    for i, d in ipairs(card.dots) do
        if i <= #list then
            d:ClearAllPoints(); d:SetPoint("BOTTOM", card, "BOTTOM", (i - (#list + 1) / 2) * 14, 50)
            d:SetStyle(i == cur and COL.red or COL.dim, i ~= cur); d:Show()
        else d:Hide() end
    end
    -- boutons
    card.skip:SetLabel(T("tutoSkip"))
    card.prev:SetShown(page > 1); card.prev:SetLabel("<  " .. T("tutoPrev"))
    card.go:SetLabel(p.welcome and (T("tutoStart") .. "  >") or last and T("tutoEnd") or (T("tutoNext") .. "  >"))
    card.go:SetWidth(p.welcome and 140 or 100)
    card:SetHeight(math.floor((card.text:GetStringHeight() or 40) + 150))
    -- trou + place de la bulle
    local l, b, r, t
    if p.target then
        local ok, parts = pcall(p.target)
        if ok then l, b, r, t = RectOf(parts, 6, p.header) end
    end
    if l then
        SetHole(l, b, r, t)
        if p.key and DB then DB.tutoTips = DB.tutoTips or {}; DB.tutoTips[p.key] = true end
        if (l + r) / 2 > (overlay:GetWidth() or 0) / 2 then
            card:SetPoint("TOPRIGHT", overlay, "BOTTOMLEFT", l - 20, t)   -- element a droite : bulle a gauche
        else
            card:SetPoint("TOPLEFT", overlay, "BOTTOMLEFT", r + 20, t)
        end
    else
        SetHole(nil)
        card:SetPoint("CENTER", overlay, "CENTER", 0, 40)
    end
end

local function Go(delta)
    local n = page + delta
    while n >= 1 and n <= #PAGES and not Usable(n) do n = n + delta end   -- zone absente : page sautee
    if n < 1 then return end
    if n > #PAGES then Finish(); return end
    page = n
    Render()
end

local function Build()
    if overlay then return overlay end
    overlay = CreateFrame("Frame", "WarpathTutorial", UIParent)
    overlay:Hide()   -- cache avant de poser OnHide (sinon il se declencherait des la creation)
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("FULLSCREEN_DIALOG"); overlay:SetToplevel(true)
    overlay:EnableMouse(true)   -- le voile bloque les clics vers le jeu pendant la visite
    -- voile en 4 morceaux autour du trou (dessus, dessous, gauche, droite)
    overlay.veil = {}
    for i = 1, 4 do overlay.veil[i] = Tex(overlay, { 0, 0, 0 }, 0.60, "BACKGROUND") end
    -- filet dore autour du trou, losanges aux coins
    overlay.ring = CreateFrame("Frame", nil, overlay)
    Border(overlay.ring, COL.accent, 0.9)
    for _, c in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local g = Diamond(overlay.ring, 8, COL.red); g:SetPoint("CENTER", overlay.ring, c, 0, 0)
    end

    local card = CreateFrame("Frame", nil, overlay)
    card:SetSize(380, 196); card:SetClampedToScreen(true)
    card:EnableMouse(true)
    local bg = Tex(card, COL.bg, 0.97, "BACKGROUND"); bg:SetAllPoints()
    Border(card, COL.line)
    for _, c in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local g = Diamond(card, 8, COL.gold); g:SetPoint("CENTER", card, c, 0, 0)
    end

    card.title = FS(card, 16, COL.gold, DISPLAY, "CENTER"); card.title:SetPoint("TOP", 0, -18)
    card.rule = Divider(card, 300); card.rule:SetPoint("TOP", card.title, "BOTTOM", 0, -8)
    card.text = FS(card, 12, COL.white, FONT, "CENTER"); card.text:SetWidth(320)
    card.text:SetPoint("TOP", card.rule, "BOTTOM", 0, -12)
    if card.text.SetSpacing then card.text:SetSpacing(2) end

    card.dots = {}
    for i = 1, 12 do card.dots[i] = Diamond(card, 7, COL.dim, true) end

    card.skip = FlatButton(card, 70, 24, Finish); card.skip:SetPoint("BOTTOMLEFT", 16, 14)
    card.go = FlatButton(card, 100, 24, function() Go(1) end); card.go:SetPoint("BOTTOMRIGHT", -16, 14)
    if card.go.fs then card.go.fs:SetTextColor(COL.accent[1], COL.accent[2], COL.accent[3]) end
    card.prev = FlatButton(card, 100, 24, function() Go(-1) end); card.prev:SetPoint("RIGHT", card.go, "LEFT", -8, 0)
    overlay.card = card

    overlay:SetScript("OnHide", function()
        -- Passer, Terminer, Echap (toute fermeture hors combat) = visite vue, puis la suite eventuelle
        if pending then return end
        if DB then DB.tutoSeen = true end
        if TipDelay then TipDelay(180) end   -- pas d'astuce dans les 3 minutes qui suivent la visite
        if guideWasShown == false and ShowGuide then pcall(ShowGuide, false) end
        guideWasShown = nil
        if miniWas and DB then DB.mini = true; if Refresh then pcall(Refresh, true) end end
        miniWas = nil
        local cb = onDone; onDone = nil
        if cb then
            if C_Timer and C_Timer.After then C_Timer.After(0.2, function() pcall(cb) end) else pcall(cb) end
        end
    end)
    overlay:SetScript("OnEvent", function(self, ev)
        if ev == "PLAYER_REGEN_DISABLED" then
            if self:IsShown() then pending = true; self:Hide() end
        elseif ev == "PLAYER_REGEN_ENABLED" then
            if pending then pending = false; self:Show(); Render() end
        end
    end)
    overlay:RegisterEvent("PLAYER_REGEN_DISABLED"); overlay:RegisterEvent("PLAYER_REGEN_ENABLED")
    if UISpecialFrames then table.insert(UISpecialFrames, "WarpathTutorial") end
    return overlay
end

-- force = true : meme si deja vue. after : fonction appelee a la fin de la visite (Passer, Echap...).
function ShowTutorial(force, after)
    if WARPATH_TEST or not (CreateFrame and UIParent) then return end
    if not force and (not DB or DB.tutoSeen) then return end
    if after then onDone = after end
    if InCombat() then
        -- on attend la fin du combat (au plus ~2 min)
        tries = tries + 1
        if tries <= 24 and C_Timer and C_Timer.After then C_Timer.After(5, function() ShowTutorial(force) end) end
        return
    end
    tries = 0
    -- deja ouverte (/warpath tuto pendant la visite) : rien a refaire
    if overlay and overlay:IsShown() then return end
    ns.Trace("visite guidee")
    local o = Build()
    -- le guide doit etre a l'ecran pour etre montre ; remis comme avant a la fin
    guideWasShown = DB and DB.shown and true or false
    if not guideWasShown and ShowGuide then pcall(ShowGuide, true) end
    miniWas = DB and DB.mini and true or nil
    if miniWas then DB.mini = false; if Refresh then pcall(Refresh, true) end end
    page, pending = 1, false
    o:Show()
    Render()
end

------------------------------------------------------------------
-- Astuces au bon moment : une petite bulle (sans voile, rien n'est bloque) a cote d'un element la premiere
-- fois qu'il apparait. Une fois chacune (DB.tutoTips[cle]) : vue = clic sur OK ou 25 s affichee.
-- Jamais en combat, pendant la visite, une fenetre de dialogue ou avant la bienvenue. Les boutons securises
-- (ciblage, pierre de foyer) ne sont jamais ancres : on lit leur position et on place la bulle a cote.
------------------------------------------------------------------
local TIPS = {
    { key = "arrow", head = "tipArrowHead", text = "tipArrow", target = function() return _G.WarpathArrow end },
    -- ciblage : seulement a une etape « Faire » (la ou la fenetre sert vraiment : les monstres a cibler)
    { key = "targets", head = "tipTgtHead", text = "tipTgt", target = function()
        local st = steps and current and steps[current]
        if st and st.t == "do" then return _G.WarpathTargets end
    end },
    { key = "hearth", head = "tipHearthHead", text = "tipHearth", target = function()
        local b, w = _G.WarpathHearthButton, Win()
        if b and b:IsVisible() and w and w.advice and w.advice:IsVisible() then return w.advice end
    end },
}
local tip, curTip, tipShownAt
local tipSeen = {}   -- nombre de verifications de suite ou l'element est visible (evite les apparitions eclair)
local TIP_START, TIP_GAP = 180, 300   -- 3 min apres la connexion ou la visite ; 5 min entre deux astuces
local tipReadyAt                      -- pas d'astuce avant ce moment (GetTime)
local function Now() return GetTime and GetTime() or 0 end
TipDelay = function(secs) tipReadyAt = math.max(tipReadyAt or 0, Now() + (secs or TIP_START)) end

local function TipTarget(t)
    local ok, fr = pcall(t.target)
    if ok and fr and fr.IsVisible and fr:IsVisible() then return fr end
end

local function TipPlace()
    local fr = curTip and TipTarget(curTip)
    if not fr then return false end
    local ok, l, b, r, t = pcall(function()
        local s = fr:GetEffectiveScale() / UIParent:GetEffectiveScale()
        return fr:GetLeft() * s, fr:GetBottom() * s, fr:GetRight() * s, fr:GetTop() * s
    end)
    if not ok or not (l and b and r and t) then return false end
    l, b, r, t = l - 4, b - 4, r + 4, t + 4
    tip.ring:ClearAllPoints(); tip.ring:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b); tip.ring:SetSize(r - l, t - b)
    tip.card:ClearAllPoints()
    if (l + r) / 2 > (UIParent:GetWidth() or 0) / 2 then
        tip.card:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", l - 14, t)
    else
        tip.card:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", r + 14, t)
    end
    return true
end

local function TipDone(mark)
    if curTip and mark and DB then DB.tutoTips = DB.tutoTips or {}; DB.tutoTips[curTip.key] = true; TipDelay(TIP_GAP) end
    curTip = nil
    if tip then tip:Hide() end
end

local function TipBuild()
    if tip then return tip end
    tip = CreateFrame("Frame", "WarpathTip", UIParent)
    tip:Hide()
    tip:SetAllPoints(UIParent); tip:SetFrameStrata("DIALOG")   -- pas de souris : le jeu reste cliquable
    tip.ring = CreateFrame("Frame", nil, tip)
    Border(tip.ring, COL.accent, 0.9)
    for _, c in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local g = Diamond(tip.ring, 7, COL.red); g:SetPoint("CENTER", tip.ring, c, 0, 0)
    end
    local card = CreateFrame("Frame", nil, tip)
    card:SetSize(260, 120); card:SetClampedToScreen(true); card:EnableMouse(true)
    local bg = Tex(card, COL.bg, 0.97, "BACKGROUND"); bg:SetAllPoints()
    Border(card, COL.line)
    for _, c in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local g = Diamond(card, 7, COL.gold); g:SetPoint("CENTER", card, c, 0, 0)
    end
    card.head = FS(card, 11, COL.gold, FONT, "LEFT"); card.head:SetPoint("TOPLEFT", 14, -12)
    card.text = FS(card, 11, COL.white, FONT, "LEFT"); card.text:SetWidth(232)
    card.text:SetPoint("TOPLEFT", card.head, "BOTTOMLEFT", 0, -8)
    if card.text.SetSpacing then card.text:SetSpacing(2) end
    card.ok = FlatButton(card, 70, 22, function() TipDone(true) end); card.ok:SetPoint("BOTTOMRIGHT", -12, 10)
    if card.ok.fs then card.ok.fs:SetTextColor(COL.accent[1], COL.accent[2], COL.accent[3]) end
    tip.card = card
    -- suit l'element s'il bouge (fleche deplacee, fenetre glissee)
    local acc = 0
    tip:SetScript("OnUpdate", function(_, el)
        acc = acc + (el or 0); if acc < 0.1 then return end; acc = 0
        if not TipPlace() then TipDone(false) end
    end)
    return tip
end

local function TipShow(t)
    TipBuild()
    curTip, tipShownAt = t, GetTime and GetTime() or 0
    local card = tip.card
    card.head:SetText(Caps(T(t.head)))
    card.text:SetText(T(t.text))
    card.ok:SetLabel("OK")
    card:SetHeight(math.floor((card.text:GetStringHeight() or 30) + 70))
    tip:Show()
    if not TipPlace() then TipDone(false) end
end

local function TipCheck()
    if not DB or not DB.welcomed then return end
    if not tipReadyAt then TipDelay(TIP_START) end                     -- 1er passage = connexion
    if InCombat() then if curTip then TipDone(false) end; return end   -- revient apres le combat
    if overlay and overlay:IsShown() then return end
    if PopupVisible and PopupVisible() then return end
    if curTip then
        if Now() - (tipShownAt or 0) > 25 then TipDone(true) end
        return
    end
    if Now() < tipReadyAt then return end
    local toast = _G.WarpathToast                                      -- « Quoi de neuf » affiche : on attend
    if toast and toast:IsShown() then return end
    local seen = DB.tutoTips or {}
    for _, t in ipairs(TIPS) do
        if not seen[t.key] then
            if TipTarget(t) then
                tipSeen[t.key] = (tipSeen[t.key] or 0) + 1
                if tipSeen[t.key] >= 2 then tipSeen[t.key] = 0; TipShow(t); return end
            else
                tipSeen[t.key] = 0
            end
        end
    end
end

if not WARPATH_TEST and C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(2, function() pcall(TipCheck) end)
end
