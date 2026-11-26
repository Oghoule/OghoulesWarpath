-- Oghoule's Warpath : moteur (Quartermaster.lua) - l'Intendance (v1.41).
-- En capitale, tu choisis tes arrets (entraineur de classe, maitre d'armes, metiers, banque, aubergiste,
-- hotel des ventes, maitre de vol) ; l'addon les met dans l'ordre qui demande le moins de marche et la fleche
-- les enchaine. Un arret se coche tout seul quand tu parles au PNJ (ou ouvres sa fenetre). « Quitter » ramene
-- au guide. Proposee une seule fois par personnage, a la premiere arrivee dans une capitale, jusqu'au niveau 15 ;
-- ensuite : bouton « Intendance » dans l'en-tete de la fenetre (en capitale) ou /warpath intendance.
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end
-- v1.50 : etat partage du guide (Core.lua, ns.State)
local State = ns.State
-- v1.50 : noms propres a ce fichier (sortis de DECL, Core.lua)
local QMRenderPick, QMRenderTour, QMStart, QM_CITIES, QM_MAXLVL

do
    QM_CITIES = { [1454] = "Orgrimmar", [1456] = "Thunder Bluff", [1458] = "Undercity" }
    QM_MAXLVL = 15
    local SECONDARY = { [185] = true, [129] = true, [356] = true }
    local PRIMARY = { 164, 165, 197, 171, 202, 333, 182, 186, 393 }
    local TRAINER_KINDS = { class = true, weapon = true, prof = true }

    -- capitale ou tu te trouves (carte), ou nil
    function QMCity()
        local m = PlayerPos and PlayerPos()
        local z = m and ZoneOf(m)
        return (z and QM_CITIES[z]) and z or nil
    end
    local function cityName(m)
        local ok, i = pcall(function() return C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m) end)
        return (ok and i and i.name) or QM_CITIES[m] or ""
    end
    local function dist(m, x, y)
        local me, w = PlayerWP(), WP(m, x, y)
        if me and w and me[3] == w[3] then return Dist(me[1], me[2], w[1], w[2]) end
    end
    -- PNJ le plus proche de toi parmi { {x, y, nom}, ... } sur la carte m
    local function nearestIn(m, list)
        local best, bd
        for _, e in ipairs(list or {}) do
            local d = dist(m, e[1], e[2]) or 0
            if not bd or d < bd then best, bd = e, d end
        end
        return best
    end
    -- ta pierre de foyer est-elle liee dans cette ville ?
    local function boundHere(m)
        if not GetBindLocation then return true end
        local ok, b = pcall(GetBindLocation)
        if not ok or type(b) ~= "string" or b == "" then return true end
        local n = cityName(m)
        return n ~= "" and b:lower():find(n:lower(), 1, true) ~= nil
    end

    -- Tous les arrets possibles dans la ville m, par section (classe, metiers, autres metiers, services)
    function QMCandidates(m)
        local out = { class = {}, mine = {}, others = {}, services = {} }
        local function add(sec, it) it.m = m; out[sec][#out[sec] + 1] = it end
        local CT = ns.ClassTrainers or {}
        -- entraineur de classe
        local cl = {}
        for _, e in ipairs(CT[State.myClass] or {}) do if e[1] == m then cl[#cl + 1] = { e[2], e[3], e[4] } end end
        local e = nearestIn(m, cl)
        if e then add("class", { key = "class", kind = "class", label = T("qmClass"), x = e[1], y = e[2], n = e[3],
                                 tag = DB.trainDue and T("qmNewSpells") or nil, hot = DB.trainDue and true, on = DB.trainDue and true or false }) end
        -- maitre d'armes
        local wl = {}
        for _, w in ipairs(CT.WEAPON or {}) do if w[1] == m then wl[#wl + 1] = { w[2], w[3], w[4] } end end
        e = nearestIn(m, wl)
        if e then add("class", { key = "weapon", kind = "weapon", label = T("weaponMaster"), x = e[1], y = e[2], n = e[3],
                                 tag = (not DB.wmSeen) and T("qmNeverSeen") or nil, hot = not DB.wmSeen, on = not DB.wmSeen }) end
        -- metiers : le meilleur entraineur de la ville pour chaque metier
        local known = ProfDetect and ProfDetect() or {}
        local best = {}
        for _, t in ipairs(ns.Trainers or {}) do
            if t.m == m and (not best[t.s] or (t.r or 0) > (best[t.s].r or 0)) then best[t.s] = t end
        end
        if not best[185] then   -- cuisine : parfois seulement dans la liste des entraineurs de classe
            for _, c in ipairs(CT.COOK or {}) do if c[1] == m then best[185] = { s = 185, x = c[2], y = c[3], n = c[4], r = 0 } end end
        end
        local nPrim = 0
        for _, id in ipairs(PRIMARY) do if known[id] then nPrim = nPrim + 1 end end
        local order = {}
        for _, id in ipairs(PRIMARY) do order[#order + 1] = id end
        for _, id in ipairs({ 185, 129, 356 }) do order[#order + 1] = id end
        for _, id in ipairs(order) do
            local t = best[id]
            if t then
                local rank = known[id]
                -- rang max : l'entraineur n'enseigne pas plus haut que ce que tu as deja
                local maxed = rank and (t.r or 0) > 0 and rank >= (t.r or 0) * 75
                local it = { key = "prof" .. id, kind = "prof", label = ProfName(id) .. " · " .. (t.n or ""), x = t.x, y = t.y, n = t.n,
                             grey = maxed, tag = maxed and T("qmRankMax") or nil, on = false }
                if rank or SECONDARY[id] then add("mine", it)
                else
                    if nPrim >= 2 then it.tag = T("qmTwoPrim"); it.grey = true end
                    add("others", it)
                end
            end
        end
        -- services
        local S = (ns.Services or {})[m] or {}
        for _, k in ipairs({ "bank", "inn", "ah" }) do
            e = nearestIn(m, S[k])
            if e then
                local it = { key = k, kind = k, label = T("qm_" .. k), x = e[1], y = e[2], n = e[3], on = false }
                if k == "inn" and not boundHere(m) then it.tag, it.hot, it.on = T("qmBind"), true, true end
                add("services", it)
            end
        end
        for _, fl in ipairs(FLIGHTS or {}) do
            if fl.m == m then add("services", { key = "fly", kind = "fly", label = T("qm_fly"), x = fl.x, y = fl.y, n = nil, on = false }); break end
        end
        return out
    end

    -- Tournee : ordre le plus court a partir de toi (plus proche voisin), maitre de vol a la fin (on repart)
    function QMStart(m, items)
        local rest, fly = {}, nil
        for _, it in ipairs(items) do if it.kind == "fly" then fly = it else rest[#rest + 1] = it end end
        local stops, here = {}, PlayerWP()
        while #rest > 0 do
            local bi, bd
            for k, it in ipairs(rest) do
                local w = WP(m, it.x, it.y)
                local d = (here and w and here[3] == w[3]) and Dist(here[1], here[2], w[1], w[2]) or 0
                if not bd or d < bd then bi, bd = k, d end
            end
            local it = table.remove(rest, bi)
            stops[#stops + 1] = it
            here = WP(m, it.x, it.y) or here
        end
        if fly then stops[#stops + 1] = fly end
        if #stops == 0 then return end
        local list = {}
        for _, it in ipairs(stops) do list[#list + 1] = { kind = it.kind, label = it.label, x = it.x, y = it.y, n = it.n } end
        DB.qm = { city = m, stops = list }
        if DB.wmSeen == nil then DB.wmSeen = true end
        State.lastWP = nil
        Refresh(true)
    end
    function QMCurrent()
        local q = DB and DB.qm
        if not q then return nil end
        for k, s in ipairs(q.stops) do if not s.done then return s, k, #q.stops end end
    end
    function QMQuit()
        if not (DB and DB.qm) then return end
        DB.qm = nil; State.lastWP = nil
        Refresh(true)
    end
    local function advanced()
        if not QMCurrent() then DB.qm = nil; say(T("qmDone"), true) end
        State.lastWP = nil
        Refresh(true)
    end
    function QMSkip()
        local s = QMCurrent(); if not s then return end
        s.done = true; advanced()
    end
    -- point vise par la fleche (voir StepPoint dans Near.lua)
    function QMPoint()
        local s, k, n = QMCurrent()
        if not s then return nil end
        return { m = DB.qm.city, x = s.x, y = s.y, name = s.n or s.label, kind = "qm", label = s.label, idx = k, n = n }
    end
    -- un PNJ ouvert : on coche l'arret correspondant (par son nom, sinon par son type a moins de 20 m)
    local function hit(kinds)
        local q = DB and DB.qm
        if not q then return end
        local who = UnitName and UnitName("npc")
        if type(who) ~= "string" or (issecretvalue and issecretvalue(who)) then who = nil end
        local pick
        for _, s in ipairs(q.stops) do
            if not s.done and who and s.n and s.n == who then pick = s; break end
        end
        if not pick and kinds then
            for _, s in ipairs(q.stops) do
                if not s.done and kinds[s.kind] and (dist(q.city, s.x, s.y) or 999) < 20 then pick = s; break end
            end
        end
        if pick then pick.done = true; advanced() end
    end

    ------------------------------------------------------------------ fenetre (choix puis tournee)
    local panel, pool, used, othersOpen, pick, pickCity = nil, {}, 0, false, {}, nil
    local PW = W
    local MEDIA = "Interface\\AddOns\\" .. (ADDON or "OghoulesWarpath") .. "\\Media\\"
    local function row(i)
        local r = pool[i]
        if r then return r end
        r = CreateFrame("Button", nil, panel); r:SetSize(PW - 2 * PAD, 22)
        r.sep = Tex(r, COL.faint or COL.line, 1, "ARTWORK"); r.sep:SetHeight(1); r.sep:SetPoint("TOPLEFT"); r.sep:SetPoint("TOPRIGHT")
        r.check = DiamondCheck(r, 9); r.check:SetPoint("LEFT", -3, 0)
        -- case des arrets (memes icones que les objectifs : Box / BoxDone)
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(14, 14); r.icon:SetPoint("LEFT", 0, 0)
        r.tag = FS(r, 10, COL.gold, FONT, "RIGHT"); r.tag:SetPoint("RIGHT")
        r.fs = FS(r, 12, COL.white, FONT, "LEFT"); r.fs:SetPoint("LEFT", 20, 0); r.fs:SetPoint("RIGHT", r.tag, "LEFT", -6, 0)
        if r.fs.SetWordWrap then r.fs:SetWordWrap(false) end
        r.hl = Tex(r, COL.accent, 0.07, "HIGHLIGHT"); r.hl:SetAllPoints()
        pool[i] = r
        return r
    end
    local function build()
        if panel then return end
        panel = CreateFrame("Frame", "WarpathQuartermaster", UIParent)
        panel:SetSize(PW, 200); panel:SetFrameStrata("MEDIUM")
        panel:SetPoint("TOPLEFT", f, "TOPLEFT")
        local bg = Tex(panel, COL.bg, 0.92, "BACKGROUND"); bg:SetAllPoints()
        Border(panel, COL.line, 0.8, "BORDER")
        local hbg = Tex(panel, COL.panel or COL.bg, 1, "BORDER"); hbg:SetHeight(HEAD_H or 34); hbg:SetPoint("TOPLEFT", 1, -1); hbg:SetPoint("TOPRIGHT", -1, -1)
        local hln = Tex(panel, COL.line, 1, "ARTWORK"); hln:SetHeight(1); hln:SetPoint("TOPLEFT", 0, -(HEAD_H or 34)); hln:SetPoint("TOPRIGHT", 0, -(HEAD_H or 34))
        panel.gem = Diamond(panel, 8, COL.red); panel.gem:SetPoint("LEFT", panel, "TOPLEFT", PAD - 4, -(HEAD_H or 34) / 2)
        -- v1.41 (uniformisation) : « ? » dans l'en-tete, comme le guide ; le compteur se place a sa gauche
        panel.help = HeadButton(panel, "?"); panel.help:SetPoint("RIGHT", panel, "TOPRIGHT", -6, -(HEAD_H or 34) / 2)
        panel.help:SetScript("OnEnter", function(self)
            Tip():SetOwner(self, "ANCHOR_LEFT"); Tip():AddLine(T("helpHead"))
            for k = 1, 3 do Tip():AddLine("|cffccba8f" .. T("qmHelpK" .. k) .. "|r  " .. T("qmHelpV" .. k), 1, 1, 1, true) end
            Tip():Show()
        end)
        panel.right = FS(panel, 10, COL.soft, FONT, "RIGHT"); panel.right:SetPoint("RIGHT", panel.help, "LEFT", -8, 0)
        -- titre court (« INTENDANCE ») borne par le compteur a droite : plus de chevauchement
        panel.title = FS(panel, 12, COL.white, FONT, "LEFT"); panel.title:SetPoint("LEFT", panel, "TOPLEFT", PAD + 12, -(HEAD_H or 34) / 2)
        panel.title:SetPoint("RIGHT", panel.right, "LEFT", -8, 0)
        if panel.title.SetWordWrap then panel.title:SetWordWrap(false) end
        panel.note = FS(panel, 11, COL.soft, FONT, "LEFT"); panel.note:SetWidth(PW - 2 * PAD)
        if panel.note.SetWordWrap then panel.note:SetWordWrap(true) end
        -- bloc destination (tournee)
        panel.dest = CreateFrame("Frame", nil, panel); panel.dest:SetSize(PW - 2 * PAD, 40)
        local dbg = Tex(panel.dest, COL.panel or COL.bg, 1, "BACKGROUND"); dbg:SetAllPoints()
        local dbar = Tex(panel.dest, COL.red, 1, "ARTWORK"); dbar:SetWidth(2); dbar:SetPoint("TOPLEFT"); dbar:SetPoint("BOTTOMLEFT")
        panel.dist = FS(panel.dest, 16, COL.white, DISPLAY or FONT, "RIGHT"); panel.dist:SetPoint("RIGHT", -10, 0)
        -- fleche de navigation, comme le bloc destination de la fenetre principale
        panel.arrow = panel.dest:CreateTexture(nil, "ARTWORK"); panel.arrow:SetSize(16, 16); panel.arrow:SetPoint("LEFT", 13, 0)
        panel.arrow:SetTexture(MEDIA .. "IcoNav")
        if panel.arrow.SetVertexColor then panel.arrow:SetVertexColor((COL.cream or COL.white)[1], (COL.cream or COL.white)[2], (COL.cream or COL.white)[3]) end
        panel.dname = FS(panel.dest, 12, COL.white, FONT, "LEFT"); panel.dname:SetPoint("TOPLEFT", 42, -8); panel.dname:SetPoint("RIGHT", panel.dist, "LEFT", -8, 0)
        panel.dsub = FS(panel.dest, 10, COL.soft, FONT, "LEFT"); panel.dsub:SetPoint("TOPLEFT", panel.dname, "BOTTOMLEFT", 0, -4)
        if panel.dname.SetWordWrap then panel.dname:SetWordWrap(false) end
        local half = (PW - 2 * PAD - 8) / 2
        panel.b1 = FlatButton(panel, half, 30, function() if panel.mode == "pick" then QMGo() else QMSkip() end end)
        panel.b2 = FlatButton(panel, half, 30, function() if panel.mode == "pick" then QMClosePick() else QMQuit() end end)
        for _, b in ipairs({ panel.b1, panel.b2 }) do
            if b.fs and b.fs.SetFont then b.fs:SetFont(FONT, 10, ""); b.fs:SetTextColor(COL.accent[1], COL.accent[2], COL.accent[3]) end
        end
        panel:SetClampedToScreen(true); panel:EnableMouse(true)
        -- poignee : meme taille que le guide (DB.scale) ; le guide suit, pour que les fenetres restent alignees
        ScaleGrip(panel, function() return DB.scale or 1 end, function(v)
            local l, t = panel:GetLeft(), panel:GetTop()
            DB.scale = v
            f:SetScale(v)
            if l and t then f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t); local p, _, rp, x, y = f:GetPoint(); DB.wpos = { p, rp, x, y } end
            local mf = rawget(f, "mini"); if mf and mf.SetScale then mf:SetScale(v) end
            panel:ClearAllPoints(); panel:SetPoint("TOPLEFT", f, "TOPLEFT")
        end)
        panel:Hide()
        -- distance a jour chaque seconde pendant la tournee
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(1, function()
                if panel:IsShown() and panel.mode == "tour" then
                    local p = QMPoint()
                    local d = p and dist(p.m, p.x, p.y)
                    panel.dist:SetText(d and T("dist", math.floor(d + 0.5)) or "")
                end
            end)
        end
    end
    local function layoutRows(list)
        local y = -(HEAD_H or 34) - 12
        used = 0
        local function put(fr, h, gap) fr:ClearAllPoints(); fr:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y); y = y - h - (gap or 0) end
        for _, it in ipairs(list) do
            if it.note then
                panel.note:SetText(it.note); panel.note:Show(); put(panel.note, panel.note:GetStringHeight() or 12, 8)
            elseif it.dest then
                panel.dest:Show(); put(panel.dest, 40, 10)
            else
                used = used + 1
                local r = row(used)
                r.item = it
                r.fs:SetText(it.text or ""); r.tag:SetText(it.tag or "")
                local c = it.head and COL.gold or (it.grey and (COL.dim or COL.soft)) or COL.white
                if r.fs.SetTextColor then r.fs:SetTextColor(c[1], c[2], c[3]) end
                c = it.hot and COL.accent or COL.gold
                if r.tag.SetTextColor then r.tag:SetTextColor(c[1], c[2], c[3]) end
                if r.fs.SetFont then r.fs:SetFont(FONT, it.head and 9 or 12, "") end
                r.check:SetShown(it.check ~= nil); if it.check ~= nil then r.check:SetOn(it.check) end
                r.icon:SetShown(it.icon ~= nil)
                if it.icon then r.icon:SetTexture(MEDIA .. it.icon) end
                r.fs:ClearAllPoints(); r.fs:SetPoint("LEFT", (it.check ~= nil or it.icon ~= nil) and 22 or 0, 0); r.fs:SetPoint("RIGHT", r.tag, "LEFT", -6, 0)
                r.sep:SetShown(not it.head)
                r:SetScript("OnClick", it.click)
                r:Show()
                put(r, it.head and 18 or 22, it.head and 2 or 0)
            end
        end
        for i = used + 1, #pool do pool[i]:Hide() end
        y = y - 12
        panel.b1:ClearAllPoints(); panel.b1:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
        panel.b2:ClearAllPoints(); panel.b2:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, y)
        panel:SetHeight(-y + 30 + 16)
    end

    -- Ecran 1 : choix des arrets
    function QMRenderPick()
        build()
        local m = pickCity
        local c = QMCandidates(m)
        panel.mode = "pick"
        panel.title:SetText(Caps(T("qmTitle")))
        panel.right:SetText(cityName(m))
        panel.dest:Hide(); panel.note:Hide()
        local list = {}
        local function sec(key, items, collapsible)
            if #items == 0 then return end
            local open = not collapsible or othersOpen
            list[#list + 1] = { head = true, text = Caps(T(key)) .. (collapsible and ("  " .. (open and "-" or "+")) or ""),
                                click = collapsible and function() othersOpen = not othersOpen; QMRenderPick() end or nil }
            if not open then return end
            for _, it in ipairs(items) do
                if pick[it.key] == nil then pick[it.key] = it.on and true or false end
                list[#list + 1] = { text = it.label, tag = it.tag, hot = it.hot, grey = it.grey, check = pick[it.key],
                                    click = function() pick[it.key] = not pick[it.key]; QMRenderPick() end }
            end
        end
        sec("qmSecClass", c.class); sec("qmSecMine", c.mine); sec("qmSecOthers", c.others, true); sec("qmSecServices", c.services)
        panel.b1:SetLabel(T("qmGo")); panel.b2:SetLabel(T("qmLater"))
        layoutRows(list)
        panel.cands = c
        UpdateMini()
    end
    function QMOpen(auto)
        local m = QMCity()
        if not m then say(T("qmNotCity")); return end
        if auto then DB.qmAsked = true end
        pick, pickCity, othersOpen = {}, m, false
        DB.qmPick = true
        QMRenderPick()
    end
    function QMClosePick()
        DB.qmPick = nil
        UpdateMini()
    end
    function QMGo()
        local c = panel and panel.cands
        if not c then return end
        local chosen = {}
        for _, sec in ipairs({ "class", "mine", "others", "services" }) do
            for _, it in ipairs(c[sec]) do if pick[it.key] then chosen[#chosen + 1] = it end end
        end
        DB.qmPick = nil
        if #chosen == 0 then UpdateMini(); return end
        QMStart(pickCity, chosen)
    end

    -- Ecran 2 : tournee en cours
    function QMRenderTour()
        build()
        local q = DB.qm
        local s, k, n = QMCurrent()
        if not s then return end
        panel.mode = "tour"
        panel.title:SetText(Caps(T("qmTitle")))
        panel.right:SetText(k .. " / " .. n)
        -- nom du PNJ seulement s'il n'est pas deja dans le libelle (metiers : « Mining · Brek Stonehoof »)
        local lbl = s.label or ""
        if s.n and not lbl:find(s.n, 1, true) then lbl = lbl .. " · " .. s.n end
        panel.dname:SetText(lbl)
        panel.dsub:SetText(cityName(q.city) .. "  ·  " .. string.format("%.1f, %.1f", s.x, s.y))
        local p = QMPoint(); local d = p and dist(p.m, p.x, p.y)
        panel.dist:SetText(d and T("dist", math.floor(d + 0.5)) or "")
        local list = { { dest = true } }
        for i, st in ipairs(q.stops) do
            list[#list + 1] = { icon = st.done and "BoxDone" or "Box", text = st.label, grey = st.done,
                                hot = (i == k), tag = (i == k) and T("qmNow") or nil }
        end
        panel.b1:SetLabel(T("qmSkip")); panel.b2:SetLabel(T("qmQuit"))
        panel.note:Hide()
        layoutRows(list)
    end

    -- Quelle fenetre montrer (appele par UpdateMini) : choix, tournee, ou rien
    function QMPanelState()
        if DB.qmPick and pickCity then return "pick" end
        if DB.qm and QMCurrent() then return "tour" end
        DB.qmPick = nil
        return nil
    end
    function QMShowPanel(state)
        if not state then if panel then panel:Hide() end; return end
        build()
        if panel.SetScale then panel:SetScale(DB.scale or 1) end
        if state == "tour" then QMRenderTour() end
        panel:Show()
    end

    -- Proposee une fois par personnage : premiere arrivee dans une capitale, jusqu'au niveau 15
    function CheckQuartermaster()
        if not DB or DB.qmAsked or DB.qm or DB.qmPick then return false end
        if (UnitLevel("player") or 1) > QM_MAXLVL then return false end
        if UnitAffectingCombat and UnitAffectingCombat("player") then return false end
        if IS_DUNGEON and IS_DUNGEON[DB.guide] then return false end
        if not QMCity() then return false end
        QMOpen(true)
        return true
    end

    -- PNJ ouverts : coche l'arret
    local ev = CreateFrame("Frame")
    local MAP = { TRAINER_SHOW = TRAINER_KINDS, BANKFRAME_OPENED = { bank = true }, AUCTION_HOUSE_SHOW = { ah = true },
                  TAXIMAP_OPENED = { fly = true }, GOSSIP_SHOW = { inn = true }, MERCHANT_SHOW = { inn = true } }
    for e in pairs(MAP) do pcall(ev.RegisterEvent, ev, e) end
    pcall(ev.RegisterEvent, ev, "ZONE_CHANGED_NEW_AREA")
    ev:SetScript("OnEvent", function(_, e)
        if not DB then return end
        if e == "ZONE_CHANGED_NEW_AREA" then
            -- sortie de la ville : la tournee s'arrete (le guide reprend)
            if (DB.qm or DB.qmPick) and C_Timer and C_Timer.After then
                C_Timer.After(1, function()
                    if not QMCity() then DB.qm = nil; DB.qmPick = nil; State.lastWP = nil; Refresh(true) end
                end)
            end
            return
        end
        pcall(hit, MAP[e])
    end)
end
