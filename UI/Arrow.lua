-- Oghoule's Warpath : moteur (Arrow.lua) - fleche de l'addon (style "pointe fine"), voir Core.lua
local ADDON, ns = ...
-- v1.50 : etat partage du guide (Core.lua, ns.State)
local State = ns.State
local Core = ns.Mod.Core -- v1.50 : module
local Route = ns.Mod.Route -- v1.50 : module
local Perf = ns.Mod.Perf -- v1.50 : module
local Skin = ns.Mod.Skin -- v1.50 : module
local Legs = ns.Mod.Legs -- v1.52 : chemin du GPS sur les cartes

-- La fleche tourne vers la prochaine position du trajet (arrowTarget ; v1.53 : reste sur l'etape actuelle pendant un apercu) a partir de ta position et de ton
-- orientation. Hors instance seulement : en donjon et en raid, le jeu ne donne plus ces informations.
do
    local frame, tex, gem, dist, last
    local ArrowMenu   -- (defini plus bas : menu du clic droit)

    -- v1.47 (signale par l'auteur) : changer la taille gardait fixe le point d'ancrage de la fenetre (fleche + texte),
    -- donc la fleche se decalait. Ici, le centre de la fleche (texture 64 x 64 en haut du cadre) reste au meme
    -- endroit de l'ecran ; la nouvelle position est sauvee (DB.arrowPos, en TOPLEFT).
    local function ApplyScale()
        if not frame then return end
        local s = State.DB.arrowScale or 1
        local old = frame:GetEffectiveScale()
        if math.abs((frame:GetScale() or 1) - s) < 0.001 then return end
        local cx, cy = tex:GetCenter()
        if not (cx and old and UIParent) then frame:SetScale(s); return end
        local sx, sy = cx * old, cy * old                     -- centre de la fleche, en pixels d'ecran
        frame:SetScale(s)
        local new = frame:GetEffectiveScale()
        local top = UIParent:GetTop() * UIParent:GetEffectiveScale()
        local half = tex:GetWidth() / 2
        local x, y = sx / new - half, (sy - top) / new + half    -- coin haut-gauche du cadre, en unites de la fleche
        x, y = math.floor(x * 10 + 0.5) / 10, math.floor(y * 10 + 0.5) / 10
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
        State.DB.arrowPos = { "TOPLEFT", x, y }
    end
    local ON_COURSE = math.rad(12) -- losange rouge si on vise a moins de 12 degres
    local ARRIVE = 8          -- metres : en dessous, la fleche devient un losange "tu y es"
    local AREA_IN, AREA_OUT = 50, 250  -- zone de chasse : cachee des que tu y es (50 m), revient seulement au-dela de 250 m
    local inArea, areaKey = false, nil
    local mode, lastD = nil, nil   -- v1.47 : etat affiche (« arrow », « here », « preview ») et distance ecrite

    local function Create()
        if frame then return end
        frame = CreateFrame("Frame", "WarpathArrow", UIParent)
        frame:SetSize(64, 84)
        frame:SetFrameStrata("MEDIUM")
        frame:SetClampedToScreen(true)
        frame:SetScale(State.DB.arrowScale or 1)   -- v1.47 : l'echelle avant la position (decalages en unites de la fleche)
        local p = State.DB.arrowPos
        if p then frame:SetPoint(p[1], UIParent, p[1], p[2], p[3]) else frame:SetPoint("TOP", UIParent, "TOP", 0, -140) end
        tex = frame:CreateTexture(nil, "ARTWORK")
        tex:SetSize(64, 64); tex:SetPoint("TOP")
        tex:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\Arrow")
        gem = frame:CreateTexture(nil, "OVERLAY")
        gem:SetSize(64, 64); gem:SetPoint("TOP")
        gem:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\ArrowGem")
        dist = Skin.FS(frame, 11, Skin.COL.gold, Skin.FONT, "CENTER"); dist:SetPoint("TOP", tex, "BOTTOM", 0, -2)
        -- deplacement (si la fenetre n'est pas verrouillee)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetMovable(true)
        frame:SetScript("OnDragStart", function(self) if not State.DB.locked then self:StartMoving() end end)
        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, _, x, y = self:GetPoint(1)
            State.DB.arrowPos = { point, math.floor(x + 0.5), math.floor(y + 0.5) }
        end)
        frame:SetScript("OnEnter", function(self)
            Skin.Tip():SetOwner(self, "ANCHOR_BOTTOM"); Skin.Tip():AddLine(Core.T("arrowTipShort"), 1, 1, 1, true)
            Skin.Tip():AddLine(Core.T("arrowTipKeys"), Skin.COL.soft[1], Skin.COL.soft[2], Skin.COL.soft[3], true); Skin.Tip():Show()
        end)
        frame:SetScript("OnLeave", function() Skin.Tip():Hide() end)
        -- v1.46 : Ctrl + molette = taille (sans Ctrl, la molette ne fait rien sur la fleche)
        frame:EnableMouseWheel(true)
        frame:SetScript("OnMouseWheel", function(_, delta)
            if not (IsControlKeyDown and IsControlKeyDown()) then return end
            State.DB.arrowScale = math.max(0.6, math.min(1.6, math.floor(((State.DB.arrowScale or 1) + delta * 0.05) * 20 + 0.5) / 20))
            ApplyScale()
            if ns.UI and ns.UI.RefreshOptions then pcall(ns.UI.RefreshOptions) end
        end)
        -- v1.46 : clic droit = petit menu (options de la fleche, replacer, masquer)
        frame:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" and ArrowMenu then ArrowMenu(self) end
        end)
        frame:Hide()
    end

    -- menu du clic droit : trois boutons dans un cadre de l'addon ; se ferme apres un choix, au 2e clic droit,
    -- ou 2 s apres que la souris l'a quitte
    local menu
    function ArrowMenu(anchor)
        if menu and menu:IsShown() then menu:Hide(); return end
        if not menu then
            menu = CreateFrame("Frame", "WarpathArrowMenu", UIParent)
            menu:SetSize(196, 3 * 26 + 12); menu:SetFrameStrata("DIALOG"); menu:SetClampedToScreen(true)
            local bg = menu:CreateTexture(nil, "BACKGROUND"); bg:SetColorTexture(Skin.COL.bg[1], Skin.COL.bg[2], Skin.COL.bg[3], 0.96); bg:SetAllPoints()
            Skin.Border(menu, Skin.COL.accent, 0.6)
            local items = {
                { "arrowMenuOpts", function() if ns.UI and ns.UI.OpenOptionsTab then ns.UI.OpenOptionsTab(4) end end },
                { "arrowReset", function() if ns.Arrow then ns.Arrow.Reset() end end },
                { "arrowMenuHide", function()
                    State.DB.ownArrow = false; State.lastWP = nil; Skin.Refresh(true)
                    Core.say(Core.T("arrowHidden"))
                end },
            }
            menu.btns = {}
            for k, it in ipairs(items) do
                local b = Skin.FlatButton(menu, 184, 24, function() menu:Hide(); it[2]() end)
                b:SetPoint("TOP", menu, "TOP", 0, -6 - (k - 1) * 26)
                b.key = it[1]
                menu.btns[k] = b
            end
            local idle = 0
            menu:SetScript("OnUpdate", function(self, el)
                if self:IsMouseOver() then idle = 0 else idle = idle + el; if idle > 2 then self:Hide() end end
            end)
            menu:SetScript("OnShow", function() idle = 0 end)
        end
        for _, b in ipairs(menu.btns) do b:SetLabel(Skin.Caps(Core.T(b.key))) end
        menu:ClearAllPoints(); menu:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
        menu:Show()
    end

    -- v1.46 : apercu pendant le reglage (onglet Apparence ouvert) : la fleche reste visible, droite,
    -- meme sans objectif ou une fois arrive
    local preview = false
    local function Preview()
        if not (State.DB and State.DB.wp ~= false and State.DB.ownArrow ~= false) then return end
        Create()
        if mode ~= "preview" then
            mode, lastD = "preview", nil
            tex:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\Arrow")
            dist:SetText(Skin.Caps(Core.T("arrowPreview")))
        end
        tex:SetRotation(0)
        gem:SetRotation(0); gem:SetVertexColor(0.80, 0.14, 0.18); gem:Show()
        ApplyScale()
        frame:Show()
    end

    local function Update()
        if not State.DB or State.DB.wp == false or State.DB.ownArrow == false or not Skin.arrowTarget then
            if frame then frame:Hide() end; return
        end
        local inst = IsInInstance and IsInInstance()
        if inst then if frame then frame:Hide() end; return end
        local facing = GetPlayerFacing and GetPlayerFacing()
        local me = Route.PlayerWP()
        local w = Route.WP(Skin.arrowTarget[1], Skin.arrowTarget[2], Skin.arrowTarget[3])
        if type(facing) ~= "number" or not me or not w or me[3] ~= w[3] then
            if frame then frame:Hide() end; return
        end
        Create()
        local dx, dy = w[1] - me[1], w[2] - me[2]          -- x : nord, y : ouest
        local d = math.sqrt(dx * dx + dy * dy)
        local tk = Skin.arrowTarget[1] .. ":" .. Skin.arrowTarget[2] .. ":" .. Skin.arrowTarget[3]
        if tk ~= areaKey then areaKey = tk; inArea = false end   -- nouvelle etape : on repart de zero
        if Skin.arrowTarget[4] then
            if d < AREA_IN then inArea = true elseif d > AREA_OUT then inArea = false end
            if inArea then frame:Hide(); return end
        else inArea = false end
        -- v1.47 : image et texte changes seulement quand ils changent (avant : 25 fois par seconde, texte refait a
        -- chaque fois ; mesure /warpath perf du 2026-11-25)
        if d < ARRIVE then
            if mode ~= "here" then
                mode, lastD = "here", nil
                tex:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\ArrowHere"); tex:SetRotation(0); gem:Hide()
                dist:SetText(Skin.Caps(Core.T("arrowHere")))
            end
        else
            if mode ~= "arrow" then
                mode, lastD = "arrow", nil
                tex:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\Arrow"); gem:Show()
            end
            local ang = math.atan2(dy, dx) - facing
            ang = (ang + math.pi) % (2 * math.pi) - math.pi      -- ramene entre -pi et pi
            tex:SetRotation(ang); gem:SetRotation(ang)
            if math.abs(ang) < ON_COURSE then gem:SetVertexColor(0.80, 0.14, 0.18) else gem:SetVertexColor(0.55, 0.55, 0.55) end
            local di = math.floor(d + 0.5)
            if di ~= lastD then lastD = di; dist:SetText(Skin.Caps(Core.T("dist", di))) end
        end
        ApplyScale()
        frame:Show()
    end

    -- Icone Warpath sur la minicarte (losange de l'addon), calculee comme le font les addons de cartes :
    -- taille de la minicarte en metres selon le zoom (exterieur / interieur), rotation si la minicarte tourne,
    -- et collee au bord quand l'objectif est hors de la minicarte.
    local pin, pinTex
    -- v1.46 (retour d'un joueur : il ne voyait pas ou etait l'objectif sur la carte) : halo en losange qui
    -- grandit et s'efface, derriere l'icone de la minicarte et le repere de la carte du monde (option mapPin)
    local PULSE = 1.6   -- secondes par pulsation
    local function Pulse(halo, base)
        if State.DB.mapPin == false then halo:Hide(); return end
        local ph = ((GetTime and GetTime() or 0) % PULSE) / PULSE
        local s = base * (1 + ph * 1.4)
        halo:SetSize(s, s); halo:SetAlpha(0.8 * (1 - ph)); halo:Show()
    end
    local function Halo(parent)
        local h = parent:CreateTexture(nil, "ARTWORK")
        h:SetPoint("CENTER"); h:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\Gem")
        return h
    end
    local OUT = { 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
    local IN = { 300, 240, 180, 120, 80, 50 }
    -- echelle, rotation et demi-diametre de la minicarte : demandes au jeu une seule fois par image (v1.52)
    local mm = { k = 1, c = 1, s = 0, half = 70 }
    local function MMParams(mmap)
        local zoom = (mmap.GetZoom and mmap:GetZoom() or 0) + 1
        local diam = ((IsIndoors and IsIndoors()) and IN or OUT)[zoom] or OUT[1]
        mm.c, mm.s = 1, 0
        if GetCVar and GetCVar("rotateMinimap") == "1" then
            local f = -(GetPlayerFacing and GetPlayerFacing() or 0)
            mm.c, mm.s = math.cos(f), math.sin(f)
        end
        mm.half = mmap:GetWidth() / 2
        mm.k = mm.half / (diam / 2)
        mm.square = GetMinimapShape and GetMinimapShape() == "SQUARE"
        return mm
    end
    -- position a l'ecran (par rapport au centre de la minicarte) d'un point du monde (wx, wy)
    local function MMXY(me, wx, wy)
        local dx, dy = wx - me[1], wy - me[2]                -- x : nord, y : ouest
        local sx, sy = -dy, dx                               -- a l'ecran : droite = est, haut = nord
        sx, sy = sx * mm.c - sy * mm.s, sx * mm.s + sy * mm.c
        return sx * mm.k, sy * mm.k
    end
    local function UpdatePin()
        local mmap = _G.Minimap
        if not mmap or not State.DB or State.DB.wp == false or State.DB.mmPin == false or not Skin.arrowTarget
            or (IsInInstance and IsInInstance()) then
            if pin then pin:Hide() end; return
        end
        local me = Route.PlayerWP()
        local w = Route.WP(Skin.arrowTarget[1], Skin.arrowTarget[2], Skin.arrowTarget[3])
        if not me or not w or me[3] ~= w[3] then if pin then pin:Hide() end; return end
        if not pin then
            pin = CreateFrame("Frame", "WarpathMinimapPin", mmap)
            pin:SetSize(16, 16)
            pin:SetFrameStrata(mmap:GetFrameStrata())
            pin:SetFrameLevel(mmap:GetFrameLevel() + 8)
            pinTex = pin:CreateTexture(nil, "OVERLAY"); pinTex:SetAllPoints()
            pinTex:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\ArrowHere")
            pin.halo = Halo(pin)
        end
        MMParams(mmap)
        local sx, sy = MMXY(me, w[1], w[2])
        local half = mm.half
        local r = half - 7
        local d = math.sqrt(sx * sx + sy * sy)
        local square = mm.square
        local edge = false
        if square then
            local m = math.max(math.abs(sx), math.abs(sy))
            if m > r then sx, sy = sx * r / m, sy * r / m; edge = true end
        elseif d > r then
            sx, sy = sx * r / d, sy * r / d; edge = true
        end
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", mmap, "CENTER", sx, sy)
        pin:SetAlpha(edge and 0.75 or 1)
        pin:SetSize(edge and 15 or 20, edge and 15 or 20)
        Pulse(pin.halo, edge and 15 or 20)
        pin:Show()
    end

    -- v1.46 : repere Warpath sur la carte du monde (le point jaune du jeu reste), seulement quand la carte
    -- affichee est celle de la destination. Place comme les entraineurs de Profs.lua (enfant du canevas,
    -- echelle inverse du zoom). Pas de souris : il ne gene pas les clics sur la carte.
    local wpin
    local WPIN = 26
    local function UpdateMapPin()
        local wm = _G.WorldMapFrame
        local child = wm and wm.ScrollContainer and wm.ScrollContainer.Child
        if not (child and wm:IsShown()) or not State.DB or State.DB.wp == false or State.DB.mapPin == false or not Skin.arrowTarget
            or not (wm.GetMapID and wm:GetMapID() == Skin.arrowTarget[1]) then
            if wpin then wpin:Hide() end; return
        end
        if not wpin then
            wpin = CreateFrame("Frame", "WarpathWorldMapPin", child)
            wpin:SetSize(WPIN, WPIN); wpin:SetFrameStrata("HIGH")
            wpin.halo = Halo(wpin)
            local gem = wpin:CreateTexture(nil, "OVERLAY"); gem:SetAllPoints()
            gem:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\Gem")
        end
        local cs = child:GetScale() or 1
        wpin:SetScale(1 / cs)
        wpin:ClearAllPoints()
        wpin:SetPoint("CENTER", child, "TOPLEFT", Skin.arrowTarget[2] / 100 * child:GetWidth() * cs, -Skin.arrowTarget[3] / 100 * child:GetHeight() * cs)
        Pulse(wpin.halo, WPIN)
        wpin:Show()
    end

    -- v1.52 (maquettes A + D + E choisies par l'auteur) : le trajet du GPS (Legs.lua) en perles dorees, de toi
    -- jusqu'a l'objectif, sur la minicarte (option mmPath) et sur la carte du monde (option mapPath). Seulement
    -- quand la fleche suit un trajet pre-calcule. Minicarte : perles cachees hors du rond, estompees pres du bord.
    -- v1.52 (retour de l'auteur : « beaucoup trop de points ») : l'ecart se compte en pixels a l'ecran, pas en
    -- yards (10 yards faisaient une perle tous les 3-4 px au zoom de la minicarte) ; MAXB = nombre maximum
    local BEAD_MM_PX, BEAD_WM_PX, MAXB = 18, 24, 80
    local bA, bB, bU = {}, {}, {}                -- perles calculees : segment (a, b) et position sur le segment
    local start = {}
    -- remplit bA/bB/bU tous les `gap` yards de `from` (comme un point du trajet) au bout de pts ; renvoie le nombre
    -- (la derniere perle est l'objectif lui-meme)
    local function PathBeads(from, pts, k, gap)
        local n, d = 0, gap
        local a = from
        for i = k, #pts do
            local b = pts[i]
            local L = Route.Dist(a[1], a[2], b[1], b[2]) or 0
            while d < L and n < MAXB do
                n = n + 1; bA[n], bB[n], bU[n] = a, b, d / L
                d = d + gap
            end
            d = d - L
            a = b
        end
        n = n + 1; bA[n], bB[n], bU[n] = a, a, 0
        return n
    end
    local function Bead(parent, pool, n)
        local t = pool[n]
        if not t then
            -- v1.52 (retour de l'auteur, captures) : losange dore plein avec un fin contour sombre, comme les
            -- losanges de l'addon (couleur unie tournee de 45°). Avant : texture Gem rouge (rouge), puis
            -- desaturee + teinte doree (presque invisible, trop sombre sur le terrain).
            t = CreateFrame("Frame", nil, parent)
            local g = Skin.COL.accent
            t.edge = t:CreateTexture(nil, "OVERLAY", nil, 1); t.edge:SetAllPoints()
            t.edge:SetColorTexture(0.08, 0.05, 0.03, 0.9)
            t.fill = t:CreateTexture(nil, "OVERLAY", nil, 2)
            t.fill:SetPoint("TOPLEFT", 1.5, -1.5); t.fill:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
            t.fill:SetColorTexture(g[1], g[2], g[3], 1)
            if t.edge.SetRotation then t.edge:SetRotation(math.rad(45)); t.fill:SetRotation(math.rad(45)) end
            pool[n] = t
        end
        return t
    end
    local function HideBeads(pool, from)
        for i = from, #pool do pool[i]:Hide() end
    end
    -- v1.52 (demande de l'auteur) : sans trajet pre-calcule, perles en ligne droite jusqu'au point vise par la
    -- fleche (objectif, maitre de vol, grotte...). Pas sur place dans une zone de chasse (t[4]), comme la fleche.
    -- La table est gardee tant que la cible ne change pas (Same compare les trajets par identite).
    local straightFor, straight, straightC
    local function PathFor(t)
        local pts, k, cont = Legs.LegPath(t)
        if pts or not t then return pts, k, cont end
        -- zone de chasse : ligne droite tant que tu n'y es pas (avant : jamais dessinee sur une etape « Faire »,
        -- retour de Meauha 2026-11-27) ; cachee avec la fleche une fois sur place (inArea, meme etape)
        if t[4] and inArea and areaKey == (t[1] .. ":" .. t[2] .. ":" .. t[3]) then return nil end
        if straightFor ~= t then
            straightFor, straight, straightC = t, nil, nil
            local w = Route.WP(t[1], t[2], t[3])
            if w then straight, straightC = { { w[1], w[2], t[1], t[2], t[3] } }, w[3] end
        end
        if straight then return straight, 1, straightC end
    end

    -- rien n'a bouge depuis la derniere image (position, trajet, et pour la minicarte zoom / rotation / taille) :
    -- les perles restent ou elles sont (v1.52, presque rien a l'arret)
    local mmLast, wmLast = {}, {}
    local function Same(last, a, b, c, d, e, f, g, h)
        if last[1] == a and last[2] == b and last[3] == c and last[4] == d and last[5] == e and last[6] == f
            and last[7] == g and last[8] == h then
            return true
        end
        last[1], last[2], last[3], last[4], last[5], last[6], last[7], last[8] = a, b, c, d, e, f, g, h
        return false
    end

    local mmPool, mmLayer = {}, nil
    local function UpdatePathMM()
        local mmap = _G.Minimap
        local pts, k, cont = PathFor(Skin.arrowTarget)
        local me = pts and Route.PlayerWP()
        if not (mmap and me and State.DB and State.DB.wp ~= false and State.DB.mmPath ~= false and me[3] == cont)
            or (IsInInstance and IsInInstance()) then
            HideBeads(mmPool, 1); mmLast[1] = nil; return
        end
        MMParams(mmap)
        if Same(mmLast, me[1], me[2], pts, k, mm.k, mm.c, mm.s, mm.half) then return end
        if not mmLayer then
            mmLayer = CreateFrame("Frame", nil, mmap)
            mmLayer:SetAllPoints(mmap)
            mmLayer:SetFrameStrata(mmap:GetFrameStrata())
            mmLayer:SetFrameLevel(mmap:GetFrameLevel() + 6)   -- sous le losange (+8)
        end
        start[1], start[2] = me[1], me[2]
        local n = PathBeads(start, pts, k, math.max(4, BEAD_MM_PX / math.max(mm.k, 0.01)))
        local square = mm.square
        local r = mm.half - 4
        for i = 1, n do
            local a, b, u = bA[i], bB[i], bU[i]
            local sx, sy = MMXY(me, a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u)
            local d = square and math.max(math.abs(sx), math.abs(sy)) or math.sqrt(sx * sx + sy * sy)
            local t = Bead(mmLayer, mmPool, i)
            if d > r then
                t:Hide()
            else
                local size = (i == n) and 10 or 6
                t:SetSize(size, size)
                t:ClearAllPoints(); t:SetPoint("CENTER", mmap, "CENTER", sx, sy)
                t:SetAlpha(d > r - 14 and 0.4 or 0.95)
                t:Show()
            end
        end
        HideBeads(mmPool, n + 1)
    end

    local wmPool, wmLayer = {}, nil
    local function UpdatePathWM()
        local wm = _G.WorldMapFrame
        local child = wm and wm.ScrollContainer and wm.ScrollContainer.Child
        local pts, k = PathFor(Skin.arrowTarget)
        local me = pts and Route.PlayerWP()
        local pm, px, py = Route.PlayerPos()
        local shown = child and wm:IsShown() and wm.GetMapID and wm:GetMapID()
        if not (shown and me and px and State.DB and State.DB.wp ~= false and State.DB.mapPath ~= false) then
            HideBeads(wmPool, 1); wmLast[1] = nil; return
        end
        local cs = child:GetScale() or 1
        local W, H = child:GetWidth(), child:GetHeight()
        if Same(wmLast, me[1], me[2], pts, k, shown, cs, W, H) then return end
        if not wmLayer then
            wmLayer = CreateFrame("Frame", nil, child)
            wmLayer:SetAllPoints(child); wmLayer:SetFrameStrata("HIGH")
        end
        start[1], start[2], start[3], start[4], start[5] = me[1], me[2], pm, px, py
        -- pixels par yard sur la carte affichee, mesures sur le 1er bout de trajet qui y est (sinon 25 yards)
        local gap = 25
        local a0 = start
        for i = k, #pts do
            local b0 = pts[i]
            if a0[3] == shown and b0[3] == shown then
                local L = Route.Dist(a0[1], a0[2], b0[1], b0[2]) or 0
                if L > 1 then
                    local px = math.sqrt(((b0[4] - a0[4]) / 100 * W) ^ 2 + ((b0[5] - a0[5]) / 100 * H) ^ 2) * cs
                    if px > 0 then gap = math.max(5, BEAD_WM_PX * L / px) end
                    break
                end
            end
            a0 = b0
        end
        local n = PathBeads(start, pts, k, gap)
        local used = 0
        for i = 1, n do
            local a, b, u = bA[i], bB[i], bU[i]
            if a[3] == shown and b[3] == shown then          -- les deux bouts sur la carte affichee
                used = used + 1
                local t = Bead(wmLayer, wmPool, used)
                local size = ((i == n) and 13 or 9) / cs
                t:SetSize(size, size)
                t:ClearAllPoints()
                t:SetPoint("CENTER", child, "TOPLEFT", (a[4] + (b[4] - a[4]) * u) / 100 * W, -(a[5] + (b[5] - a[5]) * u) / 100 * H)
                t:SetAlpha(0.95); t:Show()
            end
        end
        HideBeads(wmPool, used + 1)
    end

    -- v1.43 (demande de l'auteur) : la petite fleche du bloc destination (fenetre du guide) tourne comme la
    -- grande, meme si la grande est coupee dans les options. Fixe (vers le haut) sans direction : instance,
    -- autre carte, pas de destination, arrive. L'icone IcoNav pointe vers le haut comme Media/Arrow.
    -- Interieur (Media/IcoNavFill, meme forme) : rouge discret en fondu quand on vise juste (< 12 degres,
    -- comme le losange de la grande fleche), sous le contour.
    local fill, fillA = nil, 0
    local FILL_MAX, FILL_SPEED = 0.65, 2.5 -- opacite au maximum ; vitesse du fondu (par seconde)
    local function UpdateDestIcon(el)
        local ic = Core.f and rawget(Core.f, "dest") and Core.f.dest.arrow
        if not (ic and ic.SetRotation) then return end
        if not fill then
            fill = ic:GetParent():CreateTexture(nil, "ARTWORK", nil, -1)
            fill:SetAllPoints(ic)
            fill:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\IcoNavFill")
            fill:SetVertexColor(Skin.COL.red[1], Skin.COL.red[2], Skin.COL.red[3])
            fill:SetAlpha(0)
        end
        local ang, aim = 0, false
        local facing = GetPlayerFacing and GetPlayerFacing()
        if Skin.distTarget and type(facing) == "number" and not (IsInInstance and IsInInstance()) then
            local me = Route.PlayerWP()
            local w = Route.WP(Skin.distTarget[1], Skin.distTarget[2], Skin.distTarget[3])
            if me and w and me[3] == w[3] then
                local dx, dy = w[1] - me[1], w[2] - me[2]
                if dx * dx + dy * dy >= ARRIVE * ARRIVE then
                    ang = math.atan2(dy, dx) - facing
                    ang = (ang + math.pi) % (2 * math.pi) - math.pi
                    aim = math.abs(ang) < ON_COURSE
                end
            end
        end
        ic:SetRotation(ang); fill:SetRotation(ang)
        local target = aim and FILL_MAX or 0
        local step = FILL_SPEED * FILL_MAX * (el or 0.04)
        if fillA < target then fillA = math.min(target, fillA + step) elseif fillA > target then fillA = math.max(target, fillA - step) end
        fill:SetAlpha(fillA)
    end

    local ticker = CreateFrame("Frame")
    local acc = 0
    ticker:SetScript("OnUpdate", function(_, el)
        acc = acc + el
        if acc < 0.04 then return end
        acc = 0
        local m0 = Perf.PerfOn and Perf.PerfMem and Perf.PerfMem()                     -- v1.47 : /warpath perf
        local t0 = Perf.PerfOn and debugprofilestop and debugprofilestop()
        local ok = pcall(Update)
        if not ok and frame then frame:Hide() end
        if preview and not (frame and frame:IsShown()) then pcall(Preview) end
        if not pcall(UpdatePin) and pin then pin:Hide() end
        if not pcall(UpdateMapPin) and wpin then wpin:Hide() end
        if not pcall(UpdatePathMM) then HideBeads(mmPool, 1); mmLast[1] = nil end
        if not pcall(UpdatePathWM) then HideBeads(wmPool, 1); wmLast[1] = nil end
        pcall(UpdateDestIcon, 0.04)
        if t0 and Perf.PerfMark then Perf.PerfMark("Fleche + cartes (25/s)", debugprofilestop() - t0, m0 and (Perf.PerfMem() - m0)) end
    end)

    ns.Arrow = {
        Reset = function() State.DB.arrowPos = nil; if frame then frame:ClearAllPoints(); frame:SetPoint("TOP", UIParent, "TOP", 0, -140) end end,
        Preview = function(on) preview = on and true or false end,
    }
end
