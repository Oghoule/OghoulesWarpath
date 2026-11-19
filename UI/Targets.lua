-- Oghoule's Warpath : moteur (Targets.lua) - petite fenetre de ciblage, voir Core.lua
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end

-- Une ligne cliquable par PNJ utile a l'etape (donneur, a qui rendre, monstres, maitre de vol).
-- Chaque ligne est un bouton securise de Blizzard qui lance "/targetexact Nom" : c'est TON clic qui
-- cible, ce que Forever autorise. Les boutons securises ne peuvent pas changer pendant un combat :
-- la liste se met a jour des la fin du combat.
do
    local MAX, W, RH = 8, 190, 18
    local HDR = 26   -- hauteur de l'en-tete (v1.41)
    local ICON = {
        fly    = "Interface\\Minimap\\Tracking\\FlightMaster",
        giver  = "Interface\\AddOns\\OghoulesWarpath\\Media\\IcoAccept",
        turnin = "Interface\\AddOns\\OghoulesWarpath\\Media\\IcoTurnin",
        mob    = "Interface\\AddOns\\OghoulesWarpath\\Media\\IcoDo",
        use    = "Interface\\CURSOR\\Interact",
        talk   = "Interface\\CURSOR\\Speak",
        inn    = "Interface\\AddOns\\OghoulesWarpath\\Media\\IcoInn",    -- v1.41 : icones de l'addon (avant : celles du jeu)
        buy    = "Interface\\AddOns\\OghoulesWarpath\\Media\\IcoShop",
    }
    local panel, title, rows = nil, nil, {}
    local lastDock
    local Dock   -- definie plus bas, mais appelee par Apply (sans ca : erreur cachee par pcall, liste refaite a chaque fois)
    local wanted, shownKey, waiting

    local function Create()
        if panel then return end
        panel = CreateFrame("Frame", "WarpathTargets", UIParent)
        W = math.max(140, math.min(420, tonumber(DB.tgtW) or W))
        panel:SetSize(W, HDR + 6 + RH)
        panel:SetFrameStrata("MEDIUM")
        panel:SetClampedToScreen(true)
        local p = DB.tgtPos
        if p then panel:SetScale(p[4] or 1); panel:SetPoint(p[1], UIParent, p[1], p[2], p[3]) else panel:SetPoint("CENTER", UIParent, "CENTER", -300, -120) end
        -- clic droit : la recoller sous la fenetre du guide
        panel:SetScript("OnMouseUp", function(_, btn) if btn == "RightButton" then ns.Targets.Reset() end end)
        local bg = Tex(panel, COL.bg, 0.85, "BACKGROUND"); bg:SetAllPoints()
        local top = Tex(panel, COL.line); top:SetHeight(1); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
        local bot = Tex(panel, COL.line); bot:SetHeight(1); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT")
        -- v1.41 (uniformisation) : en-tete fin (26 px) comme les autres fenetres : bande, losange rouge, titre, « ? »
        local hbg = Tex(panel, COL.panel or COL.bg, 1, "BORDER"); hbg:SetHeight(HDR); hbg:SetPoint("TOPLEFT", 0, -1); hbg:SetPoint("TOPRIGHT", 0, -1)
        local hln = Tex(panel, COL.line, 1, "ARTWORK"); hln:SetHeight(1); hln:SetPoint("TOPLEFT", 0, -HDR); hln:SetPoint("TOPRIGHT", 0, -HDR)
        local gem = Diamond(panel, 7, COL.red); gem:SetPoint("LEFT", panel, "TOPLEFT", 10, -HDR / 2)
        title = FS(panel, 10, COL.white, FONT, "LEFT"); title:SetPoint("LEFT", panel, "TOPLEFT", 22, -HDR / 2)
        local help = HeadButton(panel, "?"); help:SetPoint("RIGHT", panel, "TOPRIGHT", -5, -HDR / 2)
        help:SetScript("OnEnter", function(self)
            Tip():SetOwner(self, "ANCHOR_RIGHT"); Tip():AddLine(T("helpHead"))
            for k = 1, 4 do Tip():AddLine("|cffccba8f" .. T("tgtHelpK" .. k) .. "|r  " .. T("tgtHelpV" .. k), 1, 1, 1, true) end
            Tip():Show()
        end)
        panel:EnableMouse(true); panel:SetMovable(true); panel:RegisterForDrag("LeftButton")
        panel:SetScript("OnDragStart", function(self) if not DB.locked and not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end end)
        panel:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, _, x, y = self:GetPoint(1)
            DB.tgtPos = { point, math.floor(x + 0.5), math.floor(y + 0.5), self:GetScale() }
        end)
        -- poignee en bas a droite : glisser pour changer la largeur (hors combat, fenetre non verrouillee)
        if panel.SetResizable then panel:SetResizable(true) end
        if panel.SetResizeBounds then panel:SetResizeBounds(140, 20, 420, 600)
        elseif panel.SetMinResize then panel:SetMinResize(140, 20); panel:SetMaxResize(420, 600) end
        local grip = CreateFrame("Button", nil, panel)
        grip:SetSize(12, 12); grip:SetPoint("BOTTOMRIGHT", -1, 1); grip:SetFrameLevel((panel:GetFrameLevel() or 1) + 10)
        local gt = grip:CreateTexture(nil, "OVERLAY"); gt:SetAllPoints()
        gt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"); gt:SetVertexColor(COL.accent[1], COL.accent[2], COL.accent[3])
        local gh = grip:CreateTexture(nil, "HIGHLIGHT"); gh:SetAllPoints(); gh:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        grip:SetScript("OnMouseDown", function()
            if DB.locked or (InCombatLockdown and InCombatLockdown()) then return end
            panel:StartSizing("RIGHT")
        end)
        grip:SetScript("OnMouseUp", function()
            panel:StopMovingOrSizing()
            DB.tgtW = math.floor((panel:GetWidth() or W) + 0.5); lastDock = nil
            local point, _, _, x, y = panel:GetPoint(1)
            if point and DB.tgtPos then DB.tgtPos = { point, math.floor(x + 0.5), math.floor(y + 0.5), panel:GetScale() } end
        end)
        grip:SetScript("OnEnter", function(self) Tip():SetOwner(self, "ANCHOR_RIGHT"); Tip():AddLine(T("tgtResize"), 1, 1, 1, true); Tip():Show() end)
        grip:SetScript("OnLeave", function() Tip():Hide() end)
        for i = 1, MAX do
            local b = CreateFrame("Button", "WarpathTarget" .. i, panel, "SecureActionButtonTemplate")
            -- largeur liee a celle de la fenetre (ancres gauche et droite) : rien a recalculer quand on l'elargit
            b:SetHeight(RH)
            b:SetPoint("TOPLEFT", 4, -HDR - 3 - (i - 1) * RH); b:SetPoint("TOPRIGHT", -4, -HDR - 3 - (i - 1) * RH)
            b:RegisterForClicks("AnyUp", "AnyDown")
            b:SetAttribute("type", "macro")
            local hl = Tex(b, COL.accent, 0.12, "HIGHLIGHT"); hl:SetAllPoints()
            -- icone du jeu (reconnue au premier coup d'oeil) dans un cadre au style de l'addon
            b.box = CreateFrame("Frame", nil, b); b.box:SetSize(16, 16); b.box:SetPoint("LEFT", 1, 0)
            local boxBg = Tex(b.box, COL.faint, 0.55, "BACKGROUND"); boxBg:SetAllPoints()
            b.edge = {}
            for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
                local e = Tex(b.box, COL.line)
                if side == "TOP" or side == "BOTTOM" then e:SetHeight(1); e:SetPoint(side .. "LEFT"); e:SetPoint(side .. "RIGHT")
                else e:SetWidth(1); e:SetPoint("TOP" .. side); e:SetPoint("BOTTOM" .. side) end
                b.edge[#b.edge + 1] = e
            end
            b.icon = b.box:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(12, 12); b.icon:SetPoint("CENTER")
            -- taux de drop toujours colle au bord droit, le nom prend le reste
            b.pct = FS(b, 11, { 1, 0.82, 0 }, FONT, "RIGHT"); b.pct:SetPoint("RIGHT", -2, 0)
            b.fs = FS(b, 11, COL.white, FONT, "LEFT"); b.fs:SetPoint("LEFT", b.box, "RIGHT", 6, 0); b.fs:SetPoint("RIGHT", b.pct, "LEFT", -6, 0)
            if i > 1 then local sep = Tex(b, COL.faint, 0.8); sep:SetHeight(1); sep:SetPoint("TOPLEFT", 20, 0); sep:SetPoint("TOPRIGHT", 0, 0) end
            if b.fs.SetWordWrap then b.fs:SetWordWrap(false) end
            b:SetScript("OnEnter", function(self)
                Tip():SetOwner(self, "ANCHOR_RIGHT")
                Tip():AddLine(self.name or "")
                Tip():AddLine(T("tgtClick"), 0.8, 0.73, 0.56, true)
                if not DB.tgtPos then Tip():AddLine(T("tgtDock"), 0.55, 0.5, 0.4, true) end
                Tip():Show()
            end)
            b:SetScript("OnLeave", function() Tip():Hide() end)
            b:Hide()
            rows[i] = b
        end
        panel:Hide()
    end

    -- Noms dans la langue du jeu. ns.NpcNames est en anglais : sur un jeu dans une autre langue, on apprend
    -- le vrai nom de chaque monstre la premiere fois qu'on le voit (plaque de nom, cible ou souris).
    local function locNames()
        if not WarpathDropDB then return {} end
        WarpathDropDB._npcLoc = WarpathDropDB._npcLoc or {}
        local loc = (GetLocale and GetLocale()) or "enUS"
        WarpathDropDB._npcLoc[loc] = WarpathDropDB._npcLoc[loc] or {}
        return WarpathDropDB._npcLoc[loc]
    end
    local function learn(unit)
        if not (GetLocale and GetLocale() ~= "enUS" and UnitGUID and UnitName) then return end
        local ok, guid = pcall(UnitGUID, unit)
        if not ok or type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return end
        local id = tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-") or "")
        if not id or not (ns.NpcNames or {})[id] then return end
        local ok2, n = pcall(UnitName, unit)
        if ok2 and type(n) == "string" and n ~= "" and not (issecretvalue and issecretvalue(n)) and locNames()[id] ~= n then
            locNames()[id] = n
            return true
        end
    end
    local lastLearn = 0
    local learnEv = CreateFrame("Frame")
    for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT" }) do pcall(learnEv.RegisterEvent, learnEv, e) end
    learnEv:SetScript("OnEvent", function(_, e, unit)
        local u = (e == "NAME_PLATE_UNIT_ADDED" and unit) or (e == "PLAYER_TARGET_CHANGED" and "target") or "mouseover"
        local ok, new = pcall(learn, u)
        -- nouveau nom appris : la liste est refaite (au plus toutes les 2 s)
        if ok and new and GetTime and GetTime() - lastLearn > 2 and ns.CoreEnv and ns.CoreEnv.Refresh then
            lastLearn = GetTime(); pcall(ns.CoreEnv.Refresh, true)
        end
    end)

    -- liste des PNJ de l'etape (sans rien toucher a l'ecran)
    local function Build(s)
        local L, seen = {}, {}
        local names = setmetatable({}, { __index = function(_, id) return locNames()[id] or (ns.NpcNames or {})[id] end })
        local function add(id, kind, pct)
            if id and not seen[id] and names[id] and #L < MAX then
                seen[id] = true; L[#L + 1] = { id = id, name = names[id], kind = kind, pct = pct }
            end
        end
        -- objectif "tuer" deja rempli (texte de l'objectif qui contient le nom du monstre)
        local function killDone(qid, npc)
            if not (C_QuestLog and C_QuestLog.GetQuestObjectives and names[npc]) then return false end
            local ok, objs = pcall(C_QuestLog.GetQuestObjectives, qid)
            if not ok or type(objs) ~= "table" then return false end
            for _, o in ipairs(objs) do
                if type(o.text) == "string" and o.text:find(names[npc], 1, true) then return o.finished and true or false end
            end
            return false
        end
        local function itemDone(item, need)
            local n = (C_Item and C_Item.GetItemCount) and C_Item.GetItemCount(item) or 0
            return (n or 0) >= (need or 1)
        end
        if currentAdvice and currentAdvice.kind == "bind" then add(currentAdvice.npc, "inn") end
        if currentAdvice and currentAdvice.kind == "buy" then add(currentAdvice.npc, "buy") end
        if flightPlan and flightPlan.from and ns.FlightNodeNpc then add(ns.FlightNodeNpc[flightPlan.from.key], "fly") end
        local groups = {}   -- un groupe par objectif : on les prend tour a tour, pour que chaque objectif ait sa place
        if s then
            for _, qid in ipairs(Ids(s)) do
                local e = EST[qid]
                if e then
                    if s.t == "accept" then for _, g in ipairs(e.g or {}) do add(g, "giver") end
                    elseif s.t == "turnin" then for _, g in ipairs(e.en or {}) do add(g, "turnin") end
                    elseif s.t == "do" and logById[qid] ~= true then
                        -- tuer, utiliser un objet sur, ou parler : l'icone le dit
                        local tt = type(e.t) == "string" and e.t:lower() or ""
                        local kk = e.u and "use" or ((tt:find("^speak") or tt:find("^talk")) and "talk") or "mob"
                        for _, k in ipairs(e.k or {}) do if not killDone(qid, k[1]) then groups[#groups + 1] = { { k[1], kk } } end end
                        for _, d in ipairs(e.d or {}) do
                            if #d >= 7 and not itemDone(d[1], d[2]) then
                                local rate, how = DropRate(d)
                                local per = ns.QuestieDropNpc and ns.QuestieDropNpc[d[1]]
                                local g = {}
                                for j = 7, #d do
                                    local r = (how ~= "measured" and per and per[d[j]]) or rate
                                    g[#g + 1] = { d[j], "mob", math.floor(r * 100 + 0.5) }
                                end
                                groups[#groups + 1] = g
                            end
                        end
                    end
                end
            end
        end
        local k = 1
        while #L < MAX do
            local any = false
            for _, g in ipairs(groups) do
                local c = g[k]
                if c then any = true; add(c[1], c[2], c[3]) end
            end
            if not any then break end
            k = k + 1
        end
        return L
    end

    local function Apply()
        if InCombatLockdown and InCombatLockdown() then waiting = true; return end
        waiting = false
        local L = wanted or {}
        local off = DB.targets == false or #L == 0 or DB.shown == false
        local key = off and "off" or ""
        if not off then for _, t in ipairs(L) do key = key .. t.id .. ":" .. (t.pct or "") .. t.kind .. "," end end
        if key == shownKey then return end
        shownKey = key
        if off then if panel then panel:Hide() end; return end
        Create()
        title:SetText(Caps(T("tgtTitle")))
        for i, b in ipairs(rows) do
            local t = L[i]
            if t then
                b.name = t.name; b.kind = t.kind
                b:SetAttribute("macrotext", "/targetexact " .. t.name)
                b.icon:SetTexture(ICON[t.kind])
                local KC = { giver = COL.accent, turnin = COL.green, mob = COL.red, use = COL.gold, talk = COL.accent, fly = COL.gold, inn = COL.soft, buy = COL.gold }
                local c = KC[t.kind] or COL.line
                for _, e in ipairs(b.edge) do e:SetColorTexture(c[1], c[2], c[3], 1) end
                -- nos icones (blanches) prennent la couleur du cadre ; celles du jeu gardent leurs couleurs
                local own = t.kind == "giver" or t.kind == "turnin" or t.kind == "mob"
                local ic = own and (t.kind == "mob" and COL.accent or c) or { 1, 1, 1 }
                if b.icon.SetVertexColor then b.icon:SetVertexColor(ic[1], ic[2], ic[3]) end
                b.fs:SetText(t.name); b.pct:SetText(t.pct and (t.pct .. " %") or "")
                b:Show()
            else
                b:SetAttribute("macrotext", nil); b:Hide()
            end
        end
        panel:SetHeight(HDR + 6 + #L * RH)
        panel:Show()
        lastDock = nil; Dock()
    end

    -- Par defaut, collee sous la fenetre du guide. Pas d'ancrage direct (un bouton securise ancre a la
    -- fenetre bloquerait ses changements de taille en combat) : on recopie sa position hors combat.
    function Dock()
        if not panel or DB.tgtPos or (InCombatLockdown and InCombatLockdown()) then return end
        local f = _G.WarpathFrame
        -- mode compact (v1.40) : collee sous la petite fenetre
        local mini = _G.WarpathMini
        if mini and mini.IsShown and mini:IsShown() then f = mini end
        local qm = _G.WarpathQuartermaster   -- Intendance (v1.41)
        if qm and qm.IsShown and qm:IsShown() then f = qm end
        if not (f and f:IsShown() and f:GetLeft()) then return end
        local sc, l, b, w = f:GetScale(), f:GetLeft(), f:GetBottom(), f:GetWidth()
        local key = sc .. ":" .. math.floor(l) .. ":" .. math.floor(b) .. ":" .. math.floor(w)
        if key == lastDock then return end
        lastDock = key
        panel:SetScale(sc)
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, b - 2)
        -- largeur choisie avec la poignee, sinon celle de la fenetre du guide
        panel:SetWidth(tonumber(DB.tgtW) or w)
    end
    -- monstres pas en vue (sans plaque de nom a l'ecran) : ligne grisee, pour savoir tout de suite sur qui cliquer.
    -- Si aucune plaque n'est visible (plaques desactivees), on ne grise rien.
    local function Dim()
        if not (C_NamePlate and C_NamePlate.GetNamePlates and UnitName) then return end
        local seen, any = {}, false
        for _, p in ipairs(C_NamePlate.GetNamePlates() or {}) do
            local tok = p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit)
            if tok then
                local ok, n = pcall(UnitName, tok)
                if ok and type(n) == "string" and not (issecretvalue and issecretvalue(n)) then seen[n] = true; any = true end
            end
        end
        -- au moins un monstre de la liste en vue, sinon on ne grise rien (noms qui ne correspondent pas, plaques cachees...)
        local match = false
        for _, b in ipairs(rows) do if b:IsShown() and seen[b.name or ""] then match = true end end
        for _, b in ipairs(rows) do
            if b:IsShown() then
                local a = (any and match and b.kind == "mob" and not seen[b.name or ""]) and 0.45 or 1
                b.fs:SetAlpha(a); b.box:SetAlpha(a)
            end
        end
    end
    local dockTick = CreateFrame("Frame")
    local dacc = 0
    dockTick:SetScript("OnUpdate", function(_, el)
        dacc = dacc + el
        if dacc < 0.25 then return end
        dacc = 0
        if panel and panel:IsShown() then pcall(Dock); pcall(Dim) end
    end)

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function() if waiting then pcall(Apply) end end)

    ns.Targets = {
        Update = function(s) wanted = Build(s); local ok = pcall(Apply); if not ok then shownKey = nil end end,
        Refresh = function() shownKey = nil; pcall(Apply) end,
        Reset = function()
            DB.tgtPos = nil
            lastDock = nil
            pcall(Dock)
        end,
    }
end
