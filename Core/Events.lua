-- Oghoule's Warpath : moteur (Events.lua) - voir Core.lua
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end
-- v1.50 : etat partage du guide (Core.lua, ns.State)
local State = ns.State

------------------------------------------------------------------
-- Evenements
------------------------------------------------------------------
ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
errShown = false
function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        if (...) ~= ADDON then return end
        -- Reprise des reglages de l'ancien HordeGuide (si son dossier est encore la, il charge HordeGuideCharDB)
        if WarpathCharDB == nil then
            if type(HordeGuideCharDB) == "table" then WarpathCharDB = HordeGuideCharDB
            else WarpathCharDB = { _new = true } end
        end
        DB = WarpathCharDB
        -- v0.44 : le marquage passe par un raccourci (bouton securise) ; on annule la desactivation automatique
        if not DB.tgtV2 then DB.tgtPos = nil; DB.tgtV2 = true end -- v0.46 : fenetre de ciblage collee sous le guide
        DB.step = DB.step or {}
        DB.done = DB.done or {}
        DB.ignored = DB.ignored or {}
        DB.seen = DB.seen or {}
        DB.dAnswer = DB.dAnswer or {}
        DB.fp = DB.fp or {}
        DB.fpLinks = DB.fpLinks or {}
        -- v1.39 : DB.fp contenait a tort les points de vol "DISTANT" (jamais decouverts). On le reconstruit
        -- a partir des liaisons vues sur la carte des vols (fpLinks), qui ne contiennent que des points connus.
        if not DB.fpV2 then
            local fp = {}
            for here, reach in pairs(DB.fpLinks) do
                fp[here] = true
                for k in pairs(reach) do fp[k] = true end
            end
            DB.fp, DB.fpV2 = fp, true
        end
        DB.lockHide = DB.lockHide or {}
        local fresh = WarpathDropDB == nil
        WarpathDropDB = WarpathDropDB or {}
        -- v1.02 : anglais par defaut ; une installation qui existait deja reste en francais
        if WarpathDropDB._lang == nil then
            WarpathDropDB._lang = (fresh and DB._new) and "en" or (DB.lang or "fr")
        end
        if DB.useFlights == nil then DB.useFlights = true end
        DB.dLater = DB.dLater or {}
        if DB.wp == nil then DB.wp = true end
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_LOGIN" then
        if DB._new then
            if type(HordeGuideCharDB) == "table" then
                for k, v in pairs(HordeGuideCharDB) do if DB[k] == nil or type(v) == "table" then DB[k] = v end end
            end
            DB._new = nil
        end
        local _, c = UnitClass("player")
        local _, r = UnitRace("player")
        State.myClass, State.myRace = c, r
        DB._class = c   -- pour etalonner le temps par monstre selon la classe (collecte.py)
        pcall(ResolveNewMaps)
        CreateUI()
        ns.Trace("bouton minicarte"); pcall(ns.UI.CreateMinimapButton)
        ns.Trace("options du jeu (Settings)"); pcall(ns.UI.RegisterBlizzardOptions)
        ns.Trace("connexion terminee")
        if C_Timer and C_Timer.After then C_Timer.After(3, function() pcall(ShowWelcome) end) end
        ScanLog()
        local key = DB.guide
        if key == "chain" then
            Guides.chain = DB.chainQ and BuildChainGuide(DB.chainQ, DB.chainSelf) or nil
            if not Guides.chain then key = DB.chainBack; DB.chainBack, DB.chainQ, DB.chainSelf = nil, nil, nil end
        end
        if key == "chain" and Guides.chain then
            -- une chaine etait en cours : on la garde
        elseif IS_DUNGEON[key] and DB.main then
            -- un donjon etait en cours : on le garde
        elseif not key or not Guides[key] or not DB.manual then
            key = AutoPick() or key
        end
        if not (key and SetGuide(key, true)) then
            say(T("noRace", tostring(r)))
            Refresh()
        else
            say(T("login", Title(State.G), State.current, #State.steps))
            if not next(DB.fp) then say(T("fpHint")) end
        end
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("QUEST_ACCEPTED")
        self:RegisterEvent("QUEST_REMOVED")
        self:RegisterEvent("QUEST_LOG_UPDATE")
        self:RegisterEvent("QUEST_TURNED_IN")
        self:RegisterEvent("PLAYER_LEVEL_UP")
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        self:RegisterEvent("TAXIMAP_OPENED")
        self:RegisterEvent("TAXIMAP_CLOSED")
        self:RegisterEvent("UI_INFO_MESSAGE")
        self:RegisterEvent("PLAYER_CONTROL_GAINED")
        self:RegisterEvent("PLAYER_CONTROL_LOST")
        self:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
        -- (Forever interdit le journal de combat aux addons : les monstres sont comptes a la fouille des corps)
        self:RegisterEvent("LOOT_OPENED")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        self:RegisterEvent("CHAT_MSG_ADDON")
        for _, ev in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "GOSSIP_SHOW", "QUEST_GREETING",
                              "PLAYER_XP_UPDATE", "TRAINER_SHOW", "PLAYER_REGEN_ENABLED" }) do self:RegisterEvent(ev) end
        ns.Comfort.TrackXP()
        if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, function() pcall(ns.Comfort.UpdateInfo) end) end
        self:RegisterEvent("GROUP_ROSTER_UPDATE")
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(ns.COMM) end
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(900, function() if IsInGuild and IsInGuild() then ns.ShareDrops("GUILD") end end)
            C_Timer.After(30, function() if IsInGuild and IsInGuild() then ns.ShareDrops("GUILD"); ns.SendVersion("GUILD", VERSION) end end)
        end
        ns.Drops.Refresh(logById, EST)
        if C_Timer and C_Timer.After then C_Timer.After(4, CheckDungeons); C_Timer.After(9, CheckClassQuests) else CheckDungeons() end
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        OnXPGain(...)
    elseif event == "LOOT_OPENED" then
        if ns.Drops.Tracking() then pcall(ns.Drops.OnLootOpened) end
    elseif event == "BAG_UPDATE_DELAYED" then
        ns.Drops.OnBagUpdate()
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        local who, fn = ...
        if who == ADDON then say(T("errBlocked", tostring(fn)), "error") end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        if prefix == ns.COMM then
            if type(msg) == "string" and msg:sub(1, 2) == "V|" then ns.OnVersion(msg:sub(3), sender, VERSION)
            else ns.OnDropMessage(msg, sender) end
        end
    elseif event == "QUEST_DETAIL" or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" or event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then
        ns.Comfort.OnQuestFrame(event)
    elseif event == "PLAYER_XP_UPDATE" then
        ns.Comfort.TrackXP()
    elseif event == "TRAINER_SHOW" then
        -- un entraineur de metier connu ne compte pas : seuls les autres (classe) effacent le rappel
        local who = UnitName and UnitName("npc")
        local prof = false
        if type(who) == "string" and not (issecretvalue and issecretvalue(who)) then
            for _, t in ipairs(ns.Trainers or {}) do if t.n == who then prof = true; break end end
        end
        if IsTradeskillTrainer then local ok, v = pcall(IsTradeskillTrainer); if ok and v then prof = true end end
        if not prof then DB.trainDue = nil end
        -- arrive chez l'entraineur vise : la fleche revient au guide
        if DB.errand and ClearErrand then ClearErrand() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.Comfort.UpdateItemButton()
    elseif event == "GROUP_ROSTER_UPDATE" then
        local n = GetNumGroupMembers and GetNumGroupMembers() or 0
        if n > 1 and n ~= (self.lastGroupN or 0) then
            local ch = (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
            ns.ShareDrops(ch); ns.SendVersion(ch, VERSION)
        end
        self.lastGroupN = n
        ScheduleAdvance()
    elseif event == "PLAYER_LEVEL_UP" then
        local nl = ...
        if type(nl) == "number" and nl % 2 == 0 then DB.trainDue = nl; if TrainReminder then pcall(TrainReminder) end end
        ScheduleAdvance()
        if C_Timer and C_Timer.After then C_Timer.After(1.5, CheckDungeons); C_Timer.After(4, CheckClassQuests); C_Timer.After(2.5, function() pcall(CheckZoneLevel) end) else CheckDungeons(); pcall(CheckZoneLevel) end
    elseif event == "QUEST_TURNED_IN" then
        local id = ...
        if id then DB.done[id] = true end
        State.peek = nil
        ScheduleAdvance()
    elseif event == "UI_INFO_MESSAGE" then
        -- "Nouveau trajet aerien decouvert" : on apprend le point de vol tout de suite
        local _, msg = ...
        if type(msg) == "string" and ERR_NEWTAXIPATH and not (issecretvalue and issecretvalue(msg)) and msg == ERR_NEWTAXIPATH then
            pcall(LearnFlightHere)
        end
    elseif event == "TAXIMAP_OPENED" then
        OnTaxiOpened()
    elseif event == "TAXIMAP_CLOSED" or event == "PLAYER_CONTROL_LOST" then
        if event == "TAXIMAP_CLOSED" then OnTaxiClosed() end
        -- decollage : la fleche passe tout de suite a la vraie destination (plus au maitre de vol)
        local function retarget() State.lastWP = nil; Refresh(true) end
        if C_Timer and C_Timer.After then C_Timer.After(0.5, retarget); C_Timer.After(2, retarget) else retarget() end
    elseif event == "PLAYER_CONTROL_GAINED" then
        if not (UnitOnTaxi and UnitOnTaxi("player")) then ns.Comfort.OnLanded() end
        -- fin d'un vol : on recalcule le trajet depuis l'endroit ou tu as atterri
        State.lastWP = nil
        Refresh(true)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        -- entree dans l'instance du donjon suivi : le journal du donjon prend le relais
        pcall(OnInstanceChange)
        -- nouveau continent / nouvelle zone : on recalcule (et la fleche passe du zeppelin a la vraie cible)
        ScheduleAdvance()
        Refresh(true)
    else
        if event == "QUEST_ACCEPTED" then State.peek = nil end
        ScheduleAdvance()
    end
end

-- Une erreur interne ne doit jamais spammer l'ecran : on la signale une seule fois dans le chat.
ev:SetScript("OnEvent", function(self, event, ...)
    local ok, err = pcall(OnEvent, self, event, ...)
    if not ok and not errShown then
        errShown = true
        say(T("errInternal", tostring(err)), "error")
    end
end)
