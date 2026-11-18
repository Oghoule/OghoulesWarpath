-- Oghoule's Warpath : moteur (Profs.lua) - tes metiers et leurs quetes.
-- Les metiers sont detectes en jeu, et tu peux les cocher ou decocher dans les options (onglet Metiers).
-- Quand tu arrives dans la zone ou commence une quete de metier qui te convient (niveau, niveau de metier),
-- l'addon te la propose une fois, comme les quetes de classe. Les choix de specialisation et les quetes faites
-- en donjon ne sont jamais proposes d'office : ils sont seulement listes dans l'onglet Metiers.
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end

do
    PROF_ORDER = { 164, 165, 197, 171, 202, 333, 182, 186, 393, 185, 129, 356 }
    -- noms anglais et francais (pour la detection par nom quand le jeu ne donne pas l'identifiant)
    PROF_NAMES = {
        [164] = { "Blacksmithing", "Forge" }, [165] = { "Leatherworking", "Travail du cuir" },
        [197] = { "Tailoring", "Couture" }, [171] = { "Alchemy", "Alchimie" },
        [202] = { "Engineering", "Ingénierie" }, [333] = { "Enchanting", "Enchantement" },
        [182] = { "Herbalism", "Herboristerie" }, [186] = { "Mining", "Minage" },
        [393] = { "Skinning", "Dépeçage" }, [185] = { "Cooking", "Cuisine" },
        [129] = { "First Aid", "Secourisme" }, [356] = { "Fishing", "Pêche" },
    }
    PROF_KEY = { [164] = "prof164", [165] = "prof165", [197] = "prof197", [171] = "prof171", [202] = "prof202", [333] = "prof333",
                 [182] = "prof182", [186] = "prof186", [393] = "prof393", [185] = "prof185", [129] = "prof129", [356] = "prof356" }
    -- nom du metier dans la langue de TON jeu (comme les noms de quetes) : d'abord le jeu, sinon la langue du client
    local SPELL = { [164] = 2018, [165] = 2108, [197] = 3908, [171] = 2259, [202] = 4036, [333] = 7411,
                    [182] = 2366, [186] = 2575, [393] = 8613, [185] = 2550, [129] = 3273, [356] = 7620 }
    local nameCache = {}
    function ProfName(id)
        if nameCache[id] then return nameCache[id] end
        local n
        if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
            local ok, v = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, id); if ok and type(v) == "string" and v ~= "" then n = v end
        end
        if not n and SPELL[id] then
            if C_Spell and C_Spell.GetSpellName then
                local ok, v = pcall(C_Spell.GetSpellName, SPELL[id]); if ok and type(v) == "string" and v ~= "" then n = v end
            end
            if not n and GetSpellInfo then
                local ok, v = pcall(GetSpellInfo, SPELL[id]); if ok and type(v) == "string" and v ~= "" then n = v end
            end
        end
        if not n then
            local loc = GetLocale and GetLocale() or "enUS"
            n = (PROF_NAMES[id] or {})[(loc == "frFR") and 2 or 1] or tostring(id)
        end
        nameCache[id] = n
        return n
    end
    local byName = {}
    for id, n in pairs(PROF_NAMES) do byName[n[1]:lower()] = id; byName[n[2]:lower()] = id end

    local detected, stamp = {}, -999
    -- metiers connus du personnage : { [skillLine] = rang }
    function ProfDetect(force)
        local now = GetTime and GetTime() or 0
        if not force and now - stamp < 5 then return detected end
        stamp = now
        local out = {}
        if GetProfessions and GetProfessionInfo then
            local list = { pcall(GetProfessions) }
            if list[1] then
                for k = 2, #list do
                    local idx = list[k]
                    if idx then
                        local ok, name, _, rank, _, _, _, line = pcall(GetProfessionInfo, idx)
                        if ok then
                            local id = (line and PROF_NAMES[line] and line) or (name and byName[name:lower()])
                            if id then out[id] = rank or 0 end
                        end
                    end
                end
            end
        end
        if not next(out) and GetNumSkillLines and GetSkillLineInfo then
            local ok, n = pcall(GetNumSkillLines)
            for i = 1, (ok and n or 0) do
                local ok2, name, header, _, rank = pcall(GetSkillLineInfo, i)
                if ok2 and name and not header and byName[name:lower()] then out[byName[name:lower()]] = rank or 0 end
            end
        end
        detected = out
        return out
    end

    -- coche des options : ton choix s'il y en a un, sinon ce que le jeu indique
    function ProfOn(id)
        DB.profs = DB.profs or {}
        if DB.profs[id] ~= nil then return DB.profs[id] end
        return ProfDetect()[id] ~= nil
    end
    function ProfSet(id, v) DB.profs = DB.profs or {}; DB.profs[id] = v and true or false end

    local function rankOk(e)
        local r = ProfDetect()[e.s]
        return r == nil or r >= (e.m or 0)   -- metier coche a la main sans rang connu : on ne bloque pas
    end

    -- quetes de metier pour tes metiers coches, dans l'ordre des niveaux
    function ProfQuestList()
        local out = {}
        for _, e in ipairs(ns.ProfQuests or {}) do
            if ProfOn(e.s) and EST[e.q] and QAvailable(e.q) then
                out[#out + 1] = { q = e.q, s = e.s, m = e.m, r = e.r, l = e.l, name = EST[e.q].n, spec = e.x, dungeon = e.d,
                                  done = Rendue(e.q), rank = rankOk(e) }
            end
        end
        table.sort(out, function(a, b) if a.r ~= b.r then return a.r < b.r end return a.q < b.q end)
        return out
    end

    local function mapOf(id) local e = EST[id]; return e and e.s and e.s[1] end

    function CheckProfQuests()
        if not DB or DB.noProfAsk or DB.guide == "chain" or IS_DUNGEON[DB.guide] or asking or not StaticPopup_Show then return end
        if PopupVisible() or (StaticPopup_Visible and (StaticPopup_Visible("WARPATH_CHAIN") or StaticPopup_Visible("WARPATH_DUNGEON"))) then return end
        if UnitAffectingCombat and UnitAffectingCombat("player") then return end
        DB.pqAsked = DB.pqAsked or {}
        local lvl = UnitLevel("player") or 1
        local here = PlayerPos and select(1, PlayerPos())
        if not here then return end
        for _, c in ipairs(ProfQuestList()) do
            if not c.done and not c.spec and not c.dungeon and c.rank and ProfDetect()[c.s] ~= nil and lvl >= c.r and lvl <= c.l + 6
                and not DB.pqAsked[c.q] and logById[c.q] == nil then
                local order = ChainFor(c.q, true)
                if order and #order > 0 then
                    -- seulement si la chaine commence dans la zone ou tu es (une suggestion en passant, pas un voyage)
                    local first = order[1]
                    if logById[first] ~= nil or mapOf(first) == here then
                        DB.pqAsked[c.q] = true
                        AskChain(c.q, true, "prof")
                        return
                    end
                end
            end
        end
    end

    -- Premiere fois a un endroit avec des entraineurs (le premier camp avec une auberge, niveau 5+) : quels metiers ?
    -- "Pas encore" : redemande a la premiere grande ville, ou 5 niveaux plus tard.
    local CAPITAL = { [1637] = true, [1638] = true, [1497] = true }
    function CheckProfIntro()
        if not DB or DB.profIntro == "done" or not StaticPopup_Show then return end
        if DB.guide == "chain" or IS_DUNGEON[DB.guide] or asking then return end
        if PopupVisible() or (StaticPopup_Visible and (StaticPopup_Visible("WARPATH_CHAIN") or StaticPopup_Visible("WARPATH_DUNGEON"))) then return end
        if UnitAffectingCombat and UnitAffectingCombat("player") then return end
        local lvl = UnitLevel("player") or 1
        local known = ProfDetect(true)
        if DB.profIntro == nil and next(known) and lvl > 6 then DB.profIntro = "done"; return end -- personnage qui a deja ses metiers
        -- nouveau personnage : on demande tout de suite (les premiers entraineurs sont dans la zone de depart) ;
        -- sinon au premier endroit ou tu te reposes
        if not (DB.profIntro == nil and lvl <= 5) and not (IsResting and IsResting()) then return end
        if DB.profIntro == "later" then
            local here = PlayerPos and select(1, PlayerPos())
            if not (CAPITAL[here] or lvl >= (DB.profIntroLvl or 0) + 5) then return end
        end
        local names = {}
        for _, id in ipairs(PROF_ORDER) do if known[id] then names[#names + 1] = ProfName(id) end end
        StaticPopupDialogs["WARPATH_PROFS"] = {
            text = "%s", button1 = T("profIntroGo"), button2 = T("profIntroNo"), button3 = T("profIntroLater"),
            timeout = 0, whileDead = true, hideOnEscape = true,
            OnAccept = function()
                DB.profIntro = "done"
                if ns.UI and ns.UI.OpenOptionsTab then ns.UI.OpenOptionsTab(8) end
                say(T("trainerHint"))
            end,
            OnCancel = function(_, _, why)
                if why == "clicked" then DB.profIntro = "done" else DB.profIntro = "later"; DB.profIntroLvl = UnitLevel("player") end
            end,
            OnAlt = function() DB.profIntro = "later"; DB.profIntroLvl = UnitLevel("player") end,
        }
        DB.profIntro = DB.profIntro or "asked"
        Popup("WARPATH_PROFS", T("profIntro") .. (#names > 0 and ("\n\n" .. T("profIntroKnown", table.concat(names, ", "))) or ""))
    end

    -- entraineur le plus proche d'une liste { {m, x, y, nom}, ... } (meme continent)
    function NearestTrainer(list)
        local me = PlayerWP and PlayerWP()
        if not me then return nil end
        local best, bd
        for _, e in ipairs(list or {}) do
            local g = WP(e[1], e[2], e[3])
            if g and g[3] == me[3] then
                local d = Dist(me[1], me[2], g[1], g[2])
                if not bd or d < bd then best, bd = e, d end
            end
        end
        return best, bd
    end
    local function mname(m)
        if MAPNAME[m] then return MAPNAME[m] end
        local ok, i = pcall(function() return C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m) end)
        return (ok and i and i.name) or ""
    end
    local function setWP(e)
        if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
            pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(e[1], e[2] / 100, e[3] / 100))
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
        end
    end
    -- nouveaux sorts : on dit ou est l'entraineur de classe le plus proche (repere sur la carte du monde)
    function TrainReminder()
        if not (DB and DB.trainDue and myClass and DB.trainer ~= false) then return end
        local e, d = NearestTrainer((ns.ClassTrainers or {})[myClass])
        if e then say(T("trainNear", e[4], mname(e[1]), math.floor(d + 0.5))) end
    end
    -- premiere visite d'une capitale : competences d'armes
    local CAPS = { [1454] = true, [1456] = true, [1458] = true }
    function CheckWeaponMaster()
        if not DB or DB.wmSeen or asking or PopupVisible() then return end
        local here = PlayerPos and select(1, PlayerPos())
        if not (here and CAPS[here]) then return end
        local list = {}
        for _, e in ipairs((ns.ClassTrainers or {}).WEAPON or {}) do if e[1] == here then list[#list + 1] = e end end
        local e = NearestTrainer(#list > 0 and list or (ns.ClassTrainers or {}).WEAPON)
        if not e then return end
        DB.wmSeen = true
        StaticPopupDialogs["WARPATH_WEAPON"] = {
            text = "%s", button1 = T("weaponGo"), button2 = T("ok"), timeout = 0, whileDead = true, hideOnEscape = true,
            OnAccept = function() setWP(e); say(T("trainerWP", e[4], T("weaponMaster"))) end,
        }
        Popup("WARPATH_WEAPON", T("weaponHint", e[4], mname(e[1])))
    end

    ------------------------------------------------------------------ entraineurs sur la carte du monde
    -- Un repere par entraineur des metiers coches (autant qu'on veut : ce sont nos propres reperes, pas le point
    -- de passage du jeu, qui lui est unique). Clic = point de passage du jeu vers cet entraineur.
    local ICONS = { [164] = "Trade_BlackSmithing", [165] = "INV_Misc_ArmorKit_17", [197] = "Trade_Tailoring", [171] = "Trade_Alchemy",
                    [202] = "Trade_Engineering", [333] = "Trade_Engraving", [182] = "Trade_Herbalism", [186] = "Trade_Mining",
                    [393] = "INV_Misc_Pelt_Wolf_01", [185] = "INV_Misc_Food_15", [129] = "Spell_Holy_SealOfSacrifice", [356] = "Trade_Fishing" }
    local RANKKEY = { [1] = "rank1", [2] = "rank2", [3] = "rank3", [4] = "rank4", [5] = "rank5", [6] = "rank6" }
    local function trainersShown() return DB and DB.trainerPins ~= false end
    local tpins, tused, tkey = {}, 0, nil
    local function tpin(i)
        local b = tpins[i]
        if b then return b end
        local child = WorldMapFrame.ScrollContainer.Child
        b = CreateFrame("Button", nil, child)
        b:SetSize(18, 18); b:SetFrameStrata("HIGH")
        b.bg = Tex(b, COL.bg, 0.9, "BACKGROUND"); b.bg:SetAllPoints()
        b.edge = {}
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local e = Tex(b, COL.accent)
            if side == "TOP" or side == "BOTTOM" then e:SetHeight(1); e:SetPoint(side .. "LEFT"); e:SetPoint(side .. "RIGHT")
            else e:SetWidth(1); e:SetPoint("TOP" .. side); e:SetPoint("BOTTOM" .. side) end
        end
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        if b.icon.SetTexCoord then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        b:SetScript("OnEnter", function(self)
            local t = Tip(); t:SetOwner(self, "ANCHOR_RIGHT")
            t:AddLine(self.t.n)
            t:AddLine(self.t.label or (ProfName(self.t.s) .. (RANKKEY[self.t.r] and (" - " .. T(RANKKEY[self.t.r])) or "")), COL.gold[1], COL.gold[2], COL.gold[3])
            t:AddLine(T("trainerClick"), COL.soft[1], COL.soft[2], COL.soft[3], true)
            t:Show()
        end)
        b:SetScript("OnLeave", function() Tip():Hide() end)
        b:SetScript("OnClick", function(self)
            local d = self.t
            if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates and d.m > 0 then
                pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(d.m, d.x / 100, d.y / 100))
                if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
                say(T("trainerWP", d.n, d.label or ProfName(d.s)))
            end
        end)
        tpins[i] = b
        return b
    end
    function TrainerPinsRefresh(force)
        if not (WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame.ScrollContainer) then return end
        local child = WorldMapFrame.ScrollContainer.Child
        local m = WorldMapFrame:GetMapID()
        local cs = child:GetScale() or 1
        local on = {}
        for _, id in ipairs(PROF_ORDER) do if ProfOn(id) then on[#on + 1] = id end end
        local key = tostring(m) .. ":" .. string.format("%.3f", cs) .. ":" .. tostring(trainersShown()) .. ":" .. table.concat(on, ",") .. ":" .. tostring(DB.trainDue) .. ":" .. tostring(DB.trainerAll)
        if not force and key == tkey then return end
        tkey = key
        for i = 1, tused do tpins[i]:Hide() end
        tused = 0
        if not trainersShown() then return end
        local want = {}
        for _, id in ipairs(on) do want[id] = true end
        local w, h = child:GetWidth(), child:GetHeight()
        local mapId = m
        local function place(t, icon, alpha)
            tused = tused + 1
            local b = tpin(tused)
            b.t = t
            b.icon:SetTexture(icon)
            b:SetAlpha(alpha or 1)
            b:SetScale(1 / cs)
            b:ClearAllPoints()
            b:SetPoint("CENTER", child, "TOPLEFT", t.x / 100 * w * cs, -t.y / 100 * h * cs)
            b:Show()
        end
        -- tous les entraineurs de metier (tes metiers coches en plein, les autres en plus pale)
        for _, t in ipairs(ns.Trainers or {}) do
            local mine = #on == 0 or want[t.s]
            if t.m and t.x and t.m == mapId and (mine or DB.trainerAll) then
                place(t, "Interface\\Icons\\" .. (ICONS[t.s] or "INV_Misc_QuestionMark"), mine and 1 or 0.55)
            end
        end
        -- entraineurs de ta classe quand de nouveaux sorts t'attendent, et maitres d'armes
        local CT = ns.ClassTrainers or {}
        if DB.trainDue and myClass then
            for _, e in ipairs(CT[myClass] or {}) do
                if e[1] == mapId then place({ m = e[1], x = e[2], y = e[3], n = e[4], label = T("classTrainer") }, "Interface\\Icons\\ClassIcon_" .. myClass:sub(1, 1) .. myClass:sub(2):lower()) end
            end
        end
        for _, e in ipairs(CT.WEAPON or {}) do
            if e[1] == mapId then place({ m = e[1], x = e[2], y = e[3], n = e[4], label = T("weaponMaster") }, "Interface\\Icons\\INV_Sword_04") end
        end
    end
    local function setupMap()
        if not (WorldMapFrame and WorldMapFrame.ScrollContainer) or WorldMapFrame._warpathTrainers then return end
        WorldMapFrame._warpathTrainers = true
        local function toggle(lblKey, tipKey, get, set)
            local cb
            cb = Chip(WorldMapFrame.ScrollContainer, function() set(not get()); cb.sync(); TrainerPinsRefresh(true) end)
            function cb.sync() cb:SetState(Caps(T(lblKey)), get()) end
            cb:SetScript("OnEnter", function(self)
                local t = Tip(); t:SetOwner(self, "ANCHOR_RIGHT"); t:AddLine(T(tipKey), COL.white[1], COL.white[2], COL.white[3], true); t:Show()
            end)
            cb:SetScript("OnLeave", function() Tip():Hide() end)
            return cb
        end
        local cb = toggle("trainerMapBtn", "trainerMapTip", trainersShown, function(v) DB.trainerPins = v end)
        local bar = MapBar()
        if bar then bar:Add(cb, 2) else cb:SetPoint("BOTTOMLEFT", 8, 34); cb:SetFrameStrata("HIGH") end
        local cb2 = toggle("trainerAllBtn", "trainerAllTip", function() return DB and DB.trainerAll and true or false end, function(v) if DB then DB.trainerAll = v end end)
        if bar then bar:Add(cb2, 2) else cb2:SetPoint("LEFT", cb, "RIGHT", 6, 0); cb2:SetFrameStrata("HIGH") end
        -- la carte peut etre prete avant tes reglages (DB) : on attend qu'ils soient charges
        local function sync() if not DB then return end; cb.sync(); cb2.sync() end
        sync()
        WorldMapFrame:HookScript("OnShow", function() ChipScale(cb, cb2); sync(); TrainerPinsRefresh(true) end)
        local acc = 0
        WorldMapFrame:HookScript("OnUpdate", function(_, el)
            acc = acc + el; if acc < 0.25 then return end; acc = 0
            ChipScale(cb, cb2)
            TrainerPinsRefresh()
        end)
    end
    if WorldMapFrame then setupMap() elseif C_Timer then C_Timer.After(2, setupMap) end

    local fr = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW", "PLAYER_UPDATE_RESTING" }) do
        pcall(fr.RegisterEvent, fr, e)
    end
    fr:SetScript("OnEvent", function(_, e)
        if not DB then return end
        if e == "SKILL_LINES_CHANGED" or e == "TRADE_SKILL_SHOW" then ProfDetect(true); return end
        local function go() pcall(CheckProfIntro); pcall(CheckProfQuests); pcall(CheckWeaponMaster) end
        if C_Timer and C_Timer.After then C_Timer.After(4, go) else go() end
    end)
end
