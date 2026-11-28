-- Oghoule's Warpath : moteur (Events.lua) - voir Core.lua
local ADDON, ns = ...
-- v1.50 : etat partage du guide (Core.lua, ns.State)
local State = ns.State
local Events = ns.Mod.Events -- v1.50 : module
local Skin = ns.Mod.Skin -- v1.50 : module
local Core = ns.Mod.Core -- v1.50 : module
-- v1.50 : module ns.Mod.Events (publie en fin de fichier pour les autres fichiers)
local ev
local Commands = ns.Mod.Commands -- v1.50 : module
local Choice = ns.Mod.Choice -- v1.52 : ecran de choix du parcours
local Profs = ns.Mod.Profs -- v1.50 : module
local Window = ns.Mod.Window -- v1.50 : module
local Flow = ns.Mod.Flow -- v1.50 : module
local Near = ns.Mod.Near -- v1.50 : module
local Est = ns.Mod.Est -- v1.50 : module
local Route = ns.Mod.Route -- v1.50 : module
local Group = ns.Mod.Group -- v1.53 : mode equipe

------------------------------------------------------------------
-- Evenements
------------------------------------------------------------------
ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
Events.errShown = false
function Events.OnEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        if (...) ~= ADDON then return end
        -- Reprise des reglages de l'ancien HordeGuide (si son dossier est encore la, il charge HordeGuideCharDB)
        if WarpathCharDB == nil then
            if type(HordeGuideCharDB) == "table" then WarpathCharDB = HordeGuideCharDB
            else WarpathCharDB = { _new = true } end
        end
        State.DB = WarpathCharDB
        -- v0.44 : le marquage passe par un raccourci (bouton securise) ; on annule la desactivation automatique
        if not State.DB.tgtV2 then State.DB.tgtPos = nil; State.DB.tgtV2 = true end -- v0.46 : fenetre de ciblage collee sous le guide
        State.DB.step = State.DB.step or {}
        State.DB.done = State.DB.done or {}
        State.DB.ignored = State.DB.ignored or {}
        State.DB.seen = State.DB.seen or {}
        State.DB.dAnswer = State.DB.dAnswer or {}
        State.DB.fp = State.DB.fp or {}
        State.DB.fpLinks = State.DB.fpLinks or {}
        -- v1.39 : DB.fp contenait a tort les points de vol "DISTANT" (jamais decouverts). On le reconstruit
        -- a partir des liaisons vues sur la carte des vols (fpLinks), qui ne contiennent que des points connus.
        if not State.DB.fpV2 then
            local fp = {}
            for here, reach in pairs(State.DB.fpLinks) do
                fp[here] = true
                for k in pairs(reach) do fp[k] = true end
            end
            State.DB.fp, State.DB.fpV2 = fp, true
        end
        State.DB.lockHide = State.DB.lockHide or {}
        local fresh = WarpathDropDB == nil
        WarpathDropDB = WarpathDropDB or {}
        -- v1.51 : fil d'Ariane retire : ses chemins gardes ne servent plus
        WarpathDropDB._trail, WarpathDropDB._trailNo = nil, nil
        -- v1.02 : anglais par defaut ; une installation qui existait deja reste en francais
        if WarpathDropDB._lang == nil then
            WarpathDropDB._lang = (fresh and State.DB._new) and "en" or (State.DB.lang or "fr")
        end
        if State.DB.useFlights == nil then State.DB.useFlights = true end
        State.DB.dLater = State.DB.dLater or {}
        if State.DB.wp == nil then State.DB.wp = true end
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_LOGIN" then
        if State.DB._new then
            if type(HordeGuideCharDB) == "table" then
                for k, v in pairs(HordeGuideCharDB) do if State.DB[k] == nil or type(v) == "table" then State.DB[k] = v end end
            end
            State.DB._new = nil
        end
        local _, c = UnitClass("player")
        local _, r = UnitRace("player")
        State.myClass, State.myRace = c, r
        State.DB._class = c   -- pour etalonner le temps par monstre selon la classe (collecte.py)
        pcall(Est.ResolveNewMaps)
        Window.CreateUI()
        ns.Trace("bouton minicarte"); pcall(ns.UI.CreateMinimapButton)
        ns.Trace("options du jeu (Settings)"); pcall(ns.UI.RegisterBlizzardOptions)
        ns.Trace("connexion terminee")
        -- v1.52 : d'abord le choix du parcours (une fois par personnage), puis la bienvenue / le Quoi de neuf
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function()
                local welcome = function() pcall(Commands.ShowWelcome) end
                if not pcall(Choice.MaybeShowChoice, welcome) then welcome() end
            end)
        end
        Core.ScanLog()
        local key = State.DB.guide
        if key == "chain" then
            -- v1.52 : quete speciale (Features/Special.lua) : son guide sp_<nom>, sinon une chaine ordinaire
            if State.DB.chainSpecial and ns.Mod.Special.Guide then Core.Guides.chain = ns.Mod.Special.Guide(State.DB.chainSpecial)
            else Core.Guides.chain = State.DB.chainQ and Est.BuildChainGuide(State.DB.chainQ, State.DB.chainSelf) or nil end
            if not Core.Guides.chain then key = State.DB.chainBack; State.DB.chainBack, State.DB.chainQ, State.DB.chainSelf, State.DB.chainSpecial = nil, nil, nil, nil end
        end
        if key == "chain" and Core.Guides.chain then
            -- une chaine etait en cours : on la garde
        elseif Core.IS_DUNGEON[key] and State.DB.main then
            -- un donjon etait en cours : on le garde
        elseif not key or not Core.Guides[key] or not State.DB.manual then
            key = Flow.AutoPick() or key
        end
        if not (key and Flow.SetGuide(key, true)) then
            Core.say(Core.T("noRace", tostring(r)))
            Skin.Refresh()
        else
            Core.say(Core.T("login", Core.Title(State.G), State.current, #State.steps))
            if not next(State.DB.fp) then Core.say(Core.T("fpHint")) end
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
            C_Timer.After(30, function() if IsInGuild and IsInGuild() then ns.ShareDrops("GUILD"); ns.SendVersion("GUILD", Core.VERSION) end end)
        end
        ns.Drops.Refresh(Core.logById, Est.EST)
        pcall(Group.Init)
        if C_Timer and C_Timer.After then C_Timer.After(4, Flow.CheckDungeons); C_Timer.After(9, Flow.CheckClassQuests) else Flow.CheckDungeons() end
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        Est.OnXPGain(...)
    elseif event == "LOOT_OPENED" then
        if ns.Drops.Tracking() then pcall(ns.Drops.OnLootOpened) end
    elseif event == "BAG_UPDATE_DELAYED" then
        ns.Drops.OnBagUpdate()
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        local who, fn = ...
        if who == ADDON then Core.say(Core.T("errBlocked", tostring(fn)), "error") end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        if prefix == ns.COMM then
            if type(msg) == "string" and msg:sub(1, 2) == "V|" then ns.OnVersion(msg:sub(3), sender, Core.VERSION)
            else ns.OnDropMessage(msg, sender) end
        elseif prefix == Group.PREFIX then
            pcall(Group.OnMessage, msg, sender)
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
        if not prof then State.DB.trainDue = nil end
        -- arrive chez l'entraineur vise : la fleche revient au guide
        if State.DB.errand and Near.ClearErrand then Near.ClearErrand() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.Comfort.UpdateItemButton()
    elseif event == "GROUP_ROSTER_UPDATE" then
        local n = GetNumGroupMembers and GetNumGroupMembers() or 0
        if n > 1 and n ~= (self.lastGroupN or 0) then
            local ch = (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
            ns.ShareDrops(ch); ns.SendVersion(ch, Core.VERSION)
        end
        self.lastGroupN = n
        pcall(Group.OnRoster)
        Flow.ScheduleAdvance()
    elseif event == "PLAYER_LEVEL_UP" then
        local nl = ...
        if type(nl) == "number" and nl % 2 == 0 then State.DB.trainDue = nl; if Profs.TrainReminder then pcall(Profs.TrainReminder) end end
        pcall(Group.OnLocalChange)
        Flow.ScheduleAdvance()
        if C_Timer and C_Timer.After then C_Timer.After(1.5, Flow.CheckDungeons); C_Timer.After(4, Flow.CheckClassQuests); C_Timer.After(2.5, function() pcall(Flow.CheckZoneLevel) end) else Flow.CheckDungeons(); pcall(Flow.CheckZoneLevel) end
    elseif event == "QUEST_TURNED_IN" then
        local id = ...
        if id then State.DB.done[id] = true end
        pcall(Group.OnTurnIn, id)
        State.peek = nil
        Flow.ScheduleAdvance()
    elseif event == "UI_INFO_MESSAGE" then
        -- "Nouveau trajet aerien decouvert" : on apprend le point de vol tout de suite
        local _, msg = ...
        if type(msg) == "string" and ERR_NEWTAXIPATH and not (issecretvalue and issecretvalue(msg)) and msg == ERR_NEWTAXIPATH then
            pcall(Route.LearnFlightHere)
        end
    elseif event == "TAXIMAP_OPENED" then
        Window.OnTaxiOpened()
    elseif event == "TAXIMAP_CLOSED" or event == "PLAYER_CONTROL_LOST" then
        if event == "TAXIMAP_CLOSED" then Window.OnTaxiClosed() end
        -- decollage : la fleche passe tout de suite a la vraie destination (plus au maitre de vol)
        local function retarget() State.lastWP = nil; Skin.Refresh(true) end
        if C_Timer and C_Timer.After then C_Timer.After(0.5, retarget); C_Timer.After(2, retarget) else retarget() end
    elseif event == "PLAYER_CONTROL_GAINED" then
        if not (UnitOnTaxi and UnitOnTaxi("player")) then ns.Comfort.OnLanded() end
        -- fin d'un vol : on recalcule le trajet depuis l'endroit ou tu as atterri
        State.lastWP = nil
        Skin.Refresh(true)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        -- entree dans l'instance du donjon suivi : le journal du donjon prend le relais
        pcall(Flow.OnInstanceChange)
        -- nouveau continent / nouvelle zone : on recalcule (et la fleche passe du zeppelin a la vraie cible)
        Flow.ScheduleAdvance()
        Skin.Refresh(true)
    else
        if event == "QUEST_ACCEPTED" then State.peek = nil end
        -- (QUEST_ACCEPTED, QUEST_REMOVED, QUEST_LOG_UPDATE) : les coequipiers recoivent les differences
        pcall(Group.OnLocalChange)
        Flow.ScheduleAdvance()
    end
end

-- Une erreur interne ne doit jamais spammer l'ecran : on la signale une seule fois dans le chat.
ev:SetScript("OnEvent", function(self, event, ...)
    local ok, err = pcall(Events.OnEvent, self, event, ...)
    if not ok and not Events.errShown then
        Events.errShown = true
        Core.say(Core.T("errInternal", tostring(err)), "error")
    end
end)

-- v1.50 : ce que ce fichier offre aux autres (ns.Mod.Events)
do
    local M = ns.Mod.Events
    M.ev = ev
end
