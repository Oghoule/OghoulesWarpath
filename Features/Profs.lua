-- Oghoule's Warpath : moteur (Profs.lua) - tes metiers et leurs quetes.
-- Les metiers sont detectes en jeu, et tu peux les cocher ou decocher dans les options (onglet Metiers).
-- Quand tu arrives dans la zone ou commence une quete de metier qui te convient (niveau, niveau de metier),
-- l'addon te la propose une fois, comme les quetes de classe. Les choix de specialisation et les quetes faites
-- en donjon ne sont jamais proposes d'office : ils sont seulement listes dans l'onglet Metiers.
local ADDON, ns = ...
-- v1.50 : etat partage du guide (Core.lua, ns.State)
local State = ns.State
local Flow = ns.Mod.Flow -- v1.50 : module
local Profs = ns.Mod.Profs -- v1.50 : module
local Core = ns.Mod.Core -- v1.50 : module
local Quartermaster = ns.Mod.Quartermaster -- v1.50 : module
-- v1.50 : module ns.Mod.Profs (publie en fin de fichier pour les autres fichiers)
local NearestTrainer, PROF_KEY, PROF_ORDER, ProfName, ProfOn, ProfQuestList, ProfSet, TrainReminder
local TrainerPinsRefresh
local Skin = ns.Mod.Skin -- v1.50 : module
local Near = ns.Mod.Near -- v1.50 : module
local Est = ns.Mod.Est -- v1.50 : module
local Route = ns.Mod.Route -- v1.50 : module
-- v1.50 : noms propres a ce fichier (sortis de DECL, Core.lua)
local CheckWeaponMaster, PROF_NAMES

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
    function Profs.ProfDetect(force)
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
        State.DB.profs = State.DB.profs or {}
        if State.DB.profs[id] ~= nil then return State.DB.profs[id] end
        return Profs.ProfDetect()[id] ~= nil
    end
    function ProfSet(id, v) State.DB.profs = State.DB.profs or {}; State.DB.profs[id] = v and true or false end

    local function rankOk(e)
        local r = Profs.ProfDetect()[e.s]
        return r == nil or r >= (e.m or 0)   -- metier coche a la main sans rang connu : on ne bloque pas
    end

    -- quetes de metier pour tes metiers coches, dans l'ordre des niveaux
    function ProfQuestList()
        local out = {}
        for _, e in ipairs(ns.ProfQuests or {}) do
            if ProfOn(e.s) and Est.EST[e.q] and Est.QAvailable(e.q) then
                out[#out + 1] = { q = e.q, s = e.s, m = e.m, r = e.r, l = e.l, name = Est.EST[e.q].n, spec = e.x, dungeon = e.d,
                                  done = Core.Rendue(e.q), rank = rankOk(e) }
            end
        end
        table.sort(out, function(a, b) if a.r ~= b.r then return a.r < b.r end return a.q < b.q end)
        return out
    end

    local function mapOf(id) local e = Est.EST[id]; return e and e.s and e.s[1] end

    function Profs.CheckProfQuests()
        if not State.DB or State.DB.noProfAsk or State.DB.guide == "chain" or Core.IS_DUNGEON[State.DB.guide] or State.asking or not StaticPopup_Show then return end
        if Skin.PopupVisible() or (StaticPopup_Visible and (StaticPopup_Visible("WARPATH_CHAIN") or StaticPopup_Visible("WARPATH_DUNGEON"))) then return end
        if UnitAffectingCombat and UnitAffectingCombat("player") then return end
        State.DB.pqAsked = State.DB.pqAsked or {}
        local lvl = UnitLevel("player") or 1
        local here = Route.PlayerPos and select(1, Route.PlayerPos())
        if not here then return end
        for _, c in ipairs(ProfQuestList()) do
            if not c.done and not c.spec and not c.dungeon and c.rank and Profs.ProfDetect()[c.s] ~= nil and lvl >= c.r and lvl <= c.l + 6
                and not State.DB.pqAsked[c.q] and Core.logById[c.q] == nil then
                local order = Est.ChainFor(c.q, true)
                if order and #order > 0 then
                    -- seulement si la chaine commence dans la zone ou tu es (une suggestion en passant, pas un voyage)
                    local first = order[1]
                    if Core.logById[first] ~= nil or mapOf(first) == here then
                        State.DB.pqAsked[c.q] = true
                        Flow.AskChain(c.q, true, "prof")
                        return
                    end
                end
            end
        end
    end

    -- Premiere fois a un endroit avec des entraineurs (le premier camp avec une auberge, niveau 5+) : quels metiers ?
    -- "Pas encore" : redemande a la premiere grande ville, ou 5 niveaux plus tard.
    local CAPITAL = { [1637] = true, [1638] = true, [1497] = true }
    function Profs.CheckProfIntro()
        if not State.DB or State.DB.profIntro == "done" or not StaticPopup_Show then return end
        if State.DB.guide == "chain" or Core.IS_DUNGEON[State.DB.guide] or State.asking then return end
        if Skin.PopupVisible() or (StaticPopup_Visible and (StaticPopup_Visible("WARPATH_CHAIN") or StaticPopup_Visible("WARPATH_DUNGEON"))) then return end
        if UnitAffectingCombat and UnitAffectingCombat("player") then return end
        local lvl = UnitLevel("player") or 1
        local known = Profs.ProfDetect(true)
        if State.DB.profIntro == nil and next(known) and lvl > 6 then State.DB.profIntro = "done"; return end -- personnage qui a deja ses metiers
        -- nouveau personnage : on demande tout de suite (les premiers entraineurs sont dans la zone de depart) ;
        -- sinon au premier endroit ou tu te reposes
        if not (State.DB.profIntro == nil and lvl <= 5) and not (IsResting and IsResting()) then return end
        if State.DB.profIntro == "later" then
            local here = Route.PlayerPos and select(1, Route.PlayerPos())
            if not (CAPITAL[here] or lvl >= (State.DB.profIntroLvl or 0) + 5) then return end
        end
        local names = {}
        for _, id in ipairs(PROF_ORDER) do if known[id] then names[#names + 1] = ProfName(id) end end
        StaticPopupDialogs["WARPATH_PROFS"] = {
            text = "%s", button1 = Core.T("profIntroGo"), button2 = Core.T("profIntroNo"), button3 = Core.T("profIntroLater"),
            timeout = 0, whileDead = true, hideOnEscape = true,
            OnAccept = function()
                State.DB.profIntro = "done"
                if ns.UI and ns.UI.OpenOptionsTab then ns.UI.OpenOptionsTab(8) end
                Core.say(Core.T("trainerHint"))
            end,
            OnCancel = function(_, _, why)
                if why == "clicked" then State.DB.profIntro = "done" else State.DB.profIntro = "later"; State.DB.profIntroLvl = UnitLevel("player") end
            end,
            OnAlt = function() State.DB.profIntro = "later"; State.DB.profIntroLvl = UnitLevel("player") end,
        }
        State.DB.profIntro = State.DB.profIntro or "asked"
        Skin.Popup("WARPATH_PROFS", Core.T("profIntro") .. (#names > 0 and ("\n\n" .. Core.T("profIntroKnown", table.concat(names, ", "))) or ""))
    end

    -- entraineur le plus proche d'une liste { {m, x, y, nom}, ... } (meme continent)
    function NearestTrainer(list)
        local me = Route.PlayerWP and Route.PlayerWP()
        if not me then return nil end
        local best, bd
        for _, e in ipairs(list or {}) do
            local g = Route.WP(e[1], e[2], e[3])
            if g and g[3] == me[3] then
                local d = Route.Dist(me[1], me[2], g[1], g[2])
                if not bd or d < bd then best, bd = e, d end
            end
        end
        return best, bd
    end
    local function mname(m)
        if Est.MAPNAME[m] then return Est.MAPNAME[m] end
        local ok, i = pcall(function() return C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m) end)
        return (ok and i and i.name) or ""
    end
    local function setWP(e)
        -- la fleche de l'addon y va (avant, seul le point du jeu changeait, et le guide l'ecrasait aussitot)
        if Near.SetErrand then Near.SetErrand(e[1], e[2], e[3], e[4]); return end
        if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
            pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(e[1], e[2] / 100, e[3] / 100))
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
        end
    end
    -- nouveaux sorts : on dit ou est l'entraineur de classe le plus proche (repere sur la carte du monde)
    function TrainReminder()
        if not (State.DB and State.DB.trainDue and State.myClass and State.DB.trainer ~= false) then return end
        local e, d = NearestTrainer((ns.ClassTrainers or {})[State.myClass])
        if e then Core.say(Core.T("trainNear", e[4], mname(e[1]), math.floor(d + 0.5))) end
    end
    -- premiere visite d'une capitale : competences d'armes
    local CAPS = { [1454] = true, [1456] = true, [1458] = true }
    function CheckWeaponMaster()
        if not State.DB or State.DB.wmSeen or State.asking or Skin.PopupVisible() then return end
        local here = Route.PlayerPos and select(1, Route.PlayerPos())
        if not (here and CAPS[here]) then return end
        -- v1.41 : plus de question pour le maitre d'armes, l'Intendance s'en charge : une seule ligne dans le chat
        -- pour la faire connaitre (premiere capitale au-dessus du niveau 15, ou l'Intendance n'est pas proposee)
        if Quartermaster.QMOpen then
            State.DB.wmSeen = true
            if not State.DB.qmHint then State.DB.qmHint = true; Core.say(Core.T("qmHint")) end
            return
        end
        local list = {}
        for _, e in ipairs((ns.ClassTrainers or {}).WEAPON or {}) do if e[1] == here then list[#list + 1] = e end end
        local e = NearestTrainer(#list > 0 and list or (ns.ClassTrainers or {}).WEAPON)
        if not e then return end
        State.DB.wmSeen = true
        StaticPopupDialogs["WARPATH_WEAPON"] = {
            text = "%s", button1 = Core.T("weaponGo"), button2 = Core.T("ok"), timeout = 0, whileDead = true, hideOnEscape = true,
            OnAccept = function() setWP(e); Core.say(Core.T("trainerWP", e[4], Core.T("weaponMaster"))) end,
        }
        Skin.Popup("WARPATH_WEAPON", Core.T("weaponHint", e[4], mname(e[1])))
    end

    ------------------------------------------------------------------ entraineurs sur la carte du monde
    -- Un repere par entraineur des metiers coches (autant qu'on veut : ce sont nos propres reperes, pas le point
    -- de passage du jeu, qui lui est unique). Clic = point de passage du jeu vers cet entraineur.
    local ICONS = { [164] = "Trade_BlackSmithing", [165] = "INV_Misc_ArmorKit_17", [197] = "Trade_Tailoring", [171] = "Trade_Alchemy",
                    [202] = "Trade_Engineering", [333] = "Trade_Engraving", [182] = "Trade_Herbalism", [186] = "Trade_Mining",
                    [393] = "INV_Misc_Pelt_Wolf_01", [185] = "INV_Misc_Food_15", [129] = "Spell_Holy_SealOfSacrifice", [356] = "Trade_Fishing" }
    local RANKKEY = { [1] = "rank1", [2] = "rank2", [3] = "rank3", [4] = "rank4", [5] = "rank5", [6] = "rank6" }
    local function trainersShown() return State.DB and State.DB.trainerPins ~= false end
    local tpins, tused, tkey = {}, 0, nil
    local function tpin(i)
        local b = tpins[i]
        if b then return b end
        local child = WorldMapFrame.ScrollContainer.Child
        b = CreateFrame("Button", nil, child)
        b:SetSize(18, 18); b:SetFrameStrata("HIGH")
        b.bg = Skin.Tex(b, Skin.COL.bg, 0.9, "BACKGROUND"); b.bg:SetAllPoints()
        b.edge = {}
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local e = Skin.Tex(b, Skin.COL.accent)
            if side == "TOP" or side == "BOTTOM" then e:SetHeight(1); e:SetPoint(side .. "LEFT"); e:SetPoint(side .. "RIGHT")
            else e:SetWidth(1); e:SetPoint("TOP" .. side); e:SetPoint("BOTTOM" .. side) end
        end
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        if b.icon.SetTexCoord then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        b:SetScript("OnEnter", function(self)
            local t = Skin.Tip(); t:SetOwner(self, "ANCHOR_RIGHT")
            t:AddLine(self.t.n)
            t:AddLine(self.t.label or (ProfName(self.t.s) .. (RANKKEY[self.t.r] and (" - " .. Core.T(RANKKEY[self.t.r])) or "")), Skin.COL.gold[1], Skin.COL.gold[2], Skin.COL.gold[3])
            t:AddLine(Core.T("trainerClick"), Skin.COL.soft[1], Skin.COL.soft[2], Skin.COL.soft[3], true)
            t:Show()
        end)
        b:SetScript("OnLeave", function() Skin.Tip():Hide() end)
        b:SetScript("OnClick", function(self)
            local d = self.t
            if Near.SetErrand and d.m > 0 then
                Near.SetErrand(d.m, d.x, d.y, d.n)
                Core.say(Core.T("trainerWP", d.n, d.label or ProfName(d.s)))
            elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates and d.m > 0 then
                pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(d.m, d.x / 100, d.y / 100))
                if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
                Core.say(Core.T("trainerWP", d.n, d.label or ProfName(d.s)))
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
        local key = tostring(m) .. ":" .. string.format("%.3f", cs) .. ":" .. tostring(trainersShown()) .. ":" .. table.concat(on, ",") .. ":" .. tostring(State.DB.trainDue) .. ":" .. tostring(State.DB.trainerAll)
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
            if t.m and t.x and t.m == mapId and (mine or State.DB.trainerAll) then
                place(t, "Interface\\Icons\\" .. (ICONS[t.s] or "INV_Misc_QuestionMark"), mine and 1 or 0.55)
            end
        end
        -- entraineurs de ta classe quand de nouveaux sorts t'attendent, et maitres d'armes
        local CT = ns.ClassTrainers or {}
        if State.DB.trainDue and State.myClass then
            for _, e in ipairs(CT[State.myClass] or {}) do
                if e[1] == mapId then place({ m = e[1], x = e[2], y = e[3], n = e[4], label = Core.T("classTrainer") }, "Interface\\Icons\\ClassIcon_" .. State.myClass:sub(1, 1) .. State.myClass:sub(2):lower()) end
            end
        end
        for _, e in ipairs(CT.WEAPON or {}) do
            if e[1] == mapId then place({ m = e[1], x = e[2], y = e[3], n = e[4], label = Core.T("weaponMaster") }, "Interface\\Icons\\INV_Sword_04") end
        end
    end
    local function setupMap()
        if not (WorldMapFrame and WorldMapFrame.ScrollContainer) or WorldMapFrame._warpathTrainers then return end
        WorldMapFrame._warpathTrainers = true
        local function toggle(lblKey, tipKey, get, set)
            local cb
            cb = Skin.Chip(WorldMapFrame.ScrollContainer, function() set(not get()); cb.sync(); TrainerPinsRefresh(true) end)
            function cb.sync() cb:SetState(Skin.Caps(Core.T(lblKey)), get()) end
            cb:SetScript("OnEnter", function(self)
                local t = Skin.Tip(); t:SetOwner(self, "ANCHOR_RIGHT"); t:AddLine(Core.T(tipKey), Skin.COL.white[1], Skin.COL.white[2], Skin.COL.white[3], true); t:Show()
            end)
            cb:SetScript("OnLeave", function() Skin.Tip():Hide() end)
            return cb
        end
        local cb = toggle("trainerMapBtn", "trainerMapTip", trainersShown, function(v) State.DB.trainerPins = v end)
        local bar = Skin.MapBar()
        if bar then bar:Add(cb, 2) else cb:SetPoint("BOTTOMLEFT", 8, 34); cb:SetFrameStrata("HIGH") end
        local cb2 = toggle("trainerAllBtn", "trainerAllTip", function() return State.DB and State.DB.trainerAll and true or false end, function(v) if State.DB then State.DB.trainerAll = v end end)
        if bar then bar:Add(cb2, 2) else cb2:SetPoint("LEFT", cb, "RIGHT", 6, 0); cb2:SetFrameStrata("HIGH") end
        -- la carte peut etre prete avant tes reglages (DB) : on attend qu'ils soient charges
        local function sync() if not State.DB then return end; cb.sync(); cb2.sync() end
        sync()
        WorldMapFrame:HookScript("OnShow", function() Skin.ChipScale(cb, cb2); sync(); TrainerPinsRefresh(true) end)
        local acc = 0
        WorldMapFrame:HookScript("OnUpdate", function(_, el)
            acc = acc + el; if acc < 0.25 then return end; acc = 0
            Skin.ChipScale(cb, cb2)
            TrainerPinsRefresh()
        end)
    end
    if WorldMapFrame then setupMap() elseif C_Timer then C_Timer.After(2, setupMap) end

    local fr = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW", "PLAYER_UPDATE_RESTING" }) do
        pcall(fr.RegisterEvent, fr, e)
    end
    fr:SetScript("OnEvent", function(_, e)
        if not State.DB then return end
        if e == "SKILL_LINES_CHANGED" or e == "TRADE_SKILL_SHOW" then Profs.ProfDetect(true); return end
        local function go()
            -- Intendance (premiere capitale, niveau 15 max) : elle inclut le maitre d'armes, donc pas de 2e question
            local ok, qm = pcall(function() return Quartermaster.CheckQuartermaster and Quartermaster.CheckQuartermaster() end)
            if ok and qm then return end
            pcall(Profs.CheckProfIntro); pcall(Profs.CheckProfQuests)
            if not (State.DB.qm or State.DB.qmPick) then pcall(CheckWeaponMaster) end
        end
        if C_Timer and C_Timer.After then C_Timer.After(4, go) else go() end
    end)
end

-- v1.50 : ce que ce fichier offre aux autres (ns.Mod.Profs)
do
    local M = ns.Mod.Profs
    M.NearestTrainer = NearestTrainer
    M.PROF_KEY = PROF_KEY
    M.PROF_ORDER = PROF_ORDER
    M.ProfName = ProfName
    M.ProfOn = ProfOn
    M.ProfQuestList = ProfQuestList
    M.ProfSet = ProfSet
    M.TrainReminder = TrainReminder
    M.TrainerPinsRefresh = TrainerPinsRefresh
end
