-- Oghoule's Warpath : moteur
--
-- Le guide n'a pas de "curseur" fragile : a chaque evenement, il recalcule l'etape courante a partir
-- de l'etat reel du personnage (journal de quetes + quetes rendues connues du serveur + niveau).
-- Regles (dans l'ordre) :
--   1. Une quete rendue (ou ignoree avec le bouton Ignorer) = toutes ses etapes sont faites.
--   2. Ancre : les etapes "Rendre" deja faites montrent jusqu'ou tu es rendu (la derniere telle qu'au
--      moins la moitie des "Rendre" jusque-la sont faites : une quete partagee en groupe ou livree en
--      avance ne fait pas tout sauter).
--      Tout ce qui est AVANT l'ancre et que tu n'as jamais pris est considere comme saute.
--      Les quetes encore dans ton journal restent toujours a l'ecran, meme avant l'ancre.
--   3. Une quete jamais prise qui est devenue grise pour ton niveau est sautee.
--   4. Une etape Faire/Rendre dont la quete n'est ni dans ton journal ni rendue (jamais prise,
--      ou abandonnee) est sautee.
--   5. Notes, etapes optionnelles et "Niveau" : passees avec OK, ou des que la suite est faite.
-- L'etape affichee = la premiere etape qui n'est pas faite selon ces regles.
local ADDON, ns = ...
-- Environnement prive partage par tous les fichiers du moteur (Core, Route, Estimate, Skin, Flow, Window,
-- Comfort, Commands, Events) : leurs variables communes y vivent, les vraies globales du jeu restent dans _G.
local DECL = {}
for n in ("ALL_NEEDED TrailTick TrailPoint TrailCmd TrailBreak FarmSpot FmtDur PassageKey PassageFor PassageCmd FollowUpAccepts HearthButton MobZonePoint CaveDiag MapBar MAPBAR ChipScale InlineIcon STEP_TINT SetObjRows FIXED_H DiamondCheck Border SectionHead Chip STEP_ICON SetHeader SplitPlace HEAD_H OpenStepQuest ListBlock AcceptGroup LiveObjectives TraitTrees OnTheWay TrainDetour BackToNow MySpec ForgetCave DeathTip IsCaveStep CaveTrack StepPoint StepPointKey BugWindow NearestTrainer TrainReminder CheckWeaponMaster TurninGroup baseCurrent nearKind Actionable NearPick NearTick LevelWaitLines HubNotes ThenLine InDgInstance DungeonKeyForInstance OnInstanceChange DungeonInstanceMatches DungeonLore DL DungeonLogActive DungeonLogList DungeonLogHide DungeonLogRender Restorable Restore ChronAdd ChronDungeon ChronTick ChronShow ChronPreview autoGoBusy CheckZoneLevel GuideStatus ProfName TrainerPinsRefresh PROF_KEY CheckProfIntro PROF_ORDER PROF_NAMES ProfDetect ProfOn ProfSet ProfQuestList CheckProfQuests DungeonOpen DungeonReq DungeonReqText DungeonIdealShowNews Tip Popup PopupVisible HEX PvPReport JournalReport DungeonLeft DungeonDone HearthPos HearthCD Advice currentAdvice PrereqDetour BlizzArrowShown RefreshInner ShowWelcome ShowTutorial StyleSkip StyleGet SuggestDungeonForLevel ApplyPreset styleCache chainAskSelf ClassQuestList CheckClassQuests ACCENTS Advance AllDone AnalyzeChains Applies AskChain AutoPick BASE_KILL BestFlight BuildChainGuide CHAIN CHECK CLASSBIT COL CONT_FALLBACK CanFly Caps ChainFor CheckDungeons CheckDungeonsFn ClearWaypoint Compute Continent CreateUI D DB DISPLAY DOT DROP_PRIOR DROP_WEIGHT DUNGEONS Diamond Dist Divider DropRate EK EST Estimate FLIGHTS FLY_FACTOR FLY_OVERHEAD FONT FS FindAnchor FlatButton FormatNum G GATES GateNodes GreenRange Guides HasBit HasEvidence ICON INNER IS_DUNGEON IS_DUNGEON_SET Ids Ignore IsGrey KALIMDOR KILL_WORD KillTime KnownFlights LANG Lang Layout LearnGates ListDungeons ListGuides ListHas LockCandidates MAIN_ORDER MAPNAME MAXLVL MINLVL MobXP MyChain NextApplicable NodeKeyFor OBJ_SECS OnEvent OnTaxiClosed OnTaxiOpened OnXPGain LearnFlightHere SetErrand ClearErrand ErrandPoint CityGatePoint UpdateMini ToggleMini ShowGuide MINI_W MINI_PAD QM_CITIES QM_MAXLVL QMCity QMCandidates QMStart QMCurrent QMQuit QMSkip QMPoint QMRenderPick QMOpen QMClosePick QMGo QMRenderTour QMPanelState QMShowPanel CheckQuartermaster DG_LEFT_DIST CheckDungeonLeft HearthPlace adviceArgs adviceT CityCaveFor CityCavePoint POPUP_HEAD MIN_H inCommand Toast FadeIn FadeOut Shine SKIP_ICON SetSkip HeadButton Glyph ScaleGrip OptimizeFn PAD PCOL PREFIX Peek PlaceNative PlayerPos PlayerWP QAvailable QName QuestState QuestTitle QuestXP RACEBIT RIDE RUN Refresh Rendue ResolveNewMaps SPEC ScanLog ScheduleAdvance SeenKey SetChain SetGuide SetRoute SetUpcoming SetWaypoint Short Spaced StartChain StartDungeon StepDone StepText StopDungeon T TRANSPORTS Tex Title TitledRule TransportFor TravelCost UNKNOWN UpdateDistance Upper VERSION W WIND WP Walk WarpathName WorldPos ZeroDiff ZoneOf asking band blockedBy chainAskQ chainOf computingOther current depsOf desiredWP distElapsed distTarget doneCache dynOrder errShown ev f flightPlan focus gateKey gateNodes lastKill lastSample lastWP logById myClass myRace optCache peek pending pendingAccept say steps taxiGlow tomtomWP walkCache wpCache wpElapsed wpTicker"):gmatch("%S+") do DECL[n] = true end
local assigned = {}
local env = setmetatable({}, {
    __index = function(_, k) if DECL[k] and assigned[k] then return nil end return _G[k] end,
    __newindex = function(t, k, v) if DECL[k] then assigned[k] = true; rawset(t, k, v) else _G[k] = v end end,
})
ns.CoreEnv = env
-- Trace temporaire : affiche (une fois) chaque appel sensible juste avant de le faire
local traced = {}
ns.Trace = function(name)
    ns.lastTrace = { name, GetTime and GetTime() or 0 }
    if traced[name] then return end
    traced[name] = true
    if ns.traceOn and DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff8c7f62Warpath trace : " .. name .. "|r") end
end
-- Diagnostic : toute action bloquee par le jeu est notee des le chargement et affichee une fois connecte
do
    local blocked, fr = {}, CreateFrame("Frame")
    fr:RegisterEvent("ADDON_ACTION_BLOCKED"); fr:RegisterEvent("ADDON_ACTION_FORBIDDEN"); fr:RegisterEvent("PLAYER_ENTERING_WORLD")
    local function flush()
        if #blocked == 0 or not DEFAULT_CHAT_FRAME then return end
        for _, m in ipairs(blocked) do DEFAULT_CHAT_FRAME:AddMessage("|TInterface\\AddOns\\OghoulesWarpath\\Media\\Gem:12:12:0:0|t |cffcdbb8eWarpath|r : |cffc24a3eaction bloquée par le jeu|r : " .. m) end
        wipe(blocked)
    end
    fr:SetScript("OnEvent", function(_, event, who, fn)
        if event == "PLAYER_ENTERING_WORLD" then flush(); return end
        if who == ADDON then
            local m = tostring(fn) .. " (" .. event .. ")"
            -- securite : l'automatisation qui vient d'agir est coupee pour ne plus jamais declencher le blocage
            local lt = ns.lastTrace
            local OFF = { AcceptQuest = "autoQuest", CompleteQuest = "autoQuest", GetQuestReward = "autoQuest",
                          Gossip = "autoQuest", TakeTaxiNode = "autoFly", ["bouton d'objet (creation)"] = "itemBtn", ["bouton d'objet (objet)"] = "itemBtn" }
            if lt and GetTime and GetTime() - lt[2] < 2 and OFF[lt[1]] and WarpathCharDB then
                WarpathCharDB[OFF[lt[1]]] = false
                m = m .. "  ->  " .. lt[1] .. " : fonction interdite par Forever, désactivée automatiquement (Options)"
            end
            blocked[#blocked + 1] = m
            -- v1.42 : gardee dans les sauvegardes du compte (SavedVariables du .toc) pour les diagnostics, 50 dernieres
            WarpathBlockedLog = WarpathBlockedLog or {}
            table.insert(WarpathBlockedLog, date and (date("%Y-%m-%d %H:%M:%S") .. " " .. m) or m)
            while #WarpathBlockedLog > 50 do table.remove(WarpathBlockedLog, 1) end
            flush()
        end
    end)
end
-- Certaines fonctions du jeu (ex. C_Map.GetPlayerMapPosition) creent leurs objets a partir d'un "mixin"
-- qu'elles cherchent directement dans l'environnement de l'appelant, sans passer par _G :
-- on y recopie donc les mixins de Blizzard.
for k, v in pairs(_G) do
    if type(k) == "string" and k:sub(-5) == "Mixin" then rawset(env, k, v) end
end
-- Appels de carte faits depuis l'environnement global (crees avant le changement d'environnement) :
-- ces fonctions du jeu renvoient des objets Vector2D et ne fonctionnent pas depuis un environnement prive.
ns.MapAPI = {
    PlayerPos = function(m, unit)
        if not (C_Map and C_Map.GetPlayerMapPosition) then return nil end
        return C_Map.GetPlayerMapPosition(m, unit)
    end,
    WorldFromMap = function(mapID, x, y)
        if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
        return C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    end,
}
local _ENV = env
if setfenv then setfenv(1, env) end
Guides = ns.Guides or {}

DB = nil -- WarpathCharDB (par personnage)
f = nil -- fenetre principale
G, steps = nil, nil -- guide actif et ses etapes
myClass, myRace = nil, nil
current = 1             -- etape calculee
peek = nil -- etape regardee avec < > (apercu), nil sinon
focus = nil -- etape choisie en cliquant (liste "A suivre" ou debut de chaine)
dynOrder = nil -- ordre optimise des etapes de ramassage (donjons), ou nil
chainOf = {}            -- index d'etape -> { name, pos, len, first = index de la 1re etape }
OptimizeFn = nil -- defini plus bas (besoin des fonctions de carte)
flightPlan = nil -- vol conseille en ce moment ({ from, to }) pour surligner la destination
lastWP, tomtomWP = nil, nil
pending = false

D = ns.Data
CHAIN, MAXLVL, DUNGEONS, IS_DUNGEON = D.CHAIN, D.MAXLVL, D.DUNGEONS, D.IS_DUNGEON
IS_DUNGEON_SET = IS_DUNGEON

ICON = "Interface\\AddOns\\OghoulesWarpath\\Media\\Warpath64"
VERSION = "1.42"
MINLVL, MAIN_ORDER = D.MINLVL, D.MAIN_ORDER
-- v1.41 (audit) : coche de l'addon (case cochee doree, comme les objectifs) au lieu de la coche verte du jeu
CHECK = "|TInterface\\AddOns\\OghoulesWarpath\\Media\\BoxDone:12:12|t"
DOT = "|cff888888-|r"


------------------------------------------------------------------
-- Langue (francais / anglais)
------------------------------------------------------------------
LANG = ns.LANG

function Lang()
    if DB and DB.lang then return DB.lang end
    -- anglais par defaut (nouvelles installations) ; une installation existante garde le francais
    return (WarpathDropDB and WarpathDropDB._lang) or "en"
end

function T(key, ...)
    local str = LANG[Lang()][key] or LANG.fr[key] or key
    if select("#", ...) > 0 then return string.format(str, ...) end
    return str
end
ns.T = function(...) return T(...) end

function QuestTitle(id)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, t = pcall(C_QuestLog.GetTitleForQuestID, id)
        if ok and t and t ~= "" then return t end
    end
    if C_QuestLog and C_QuestLog.GetQuestInfo then
        local ok, t = pcall(C_QuestLog.GetQuestInfo, id)
        if ok and type(t) == "string" and t ~= "" then return t end
    end
end

-- Nom affiche : celui du client (francais si ton jeu est en francais), sinon le nom anglais de la base
function QName(s)
    if not s.quest then return nil end
    if type(s.id) == "number" then return QuestTitle(s.id) or s.quest end
    if type(s.id) == "table" then
        local parts = {}
        for _, id in ipairs(s.id) do
            local t = QuestTitle(id)
            if not t then return s.quest end
            parts[#parts + 1] = t
        end
        return table.concat(parts, " + ")
    end
    return s.quest
end

function StepText(s) return (Lang() == "en" and s.en and s.en ~= "") and s.en or (s.text or "") end
function Title(g) return (Lang() == "en" and g.title_en) or g.title end

-- v1.41 (audit) : DB.chatLevel = "all" (defaut) / "important" / "none".
--   important = "error" : toujours affiche (erreurs, utiles aux signalements) ; true : message important ;
--   rien : simple information. Les reponses aux commandes /warpath s'affichent toujours (inCommand).
inCommand = false
function say(msg, important)
    local lvl = DB and DB.chatLevel or "all"
    if important ~= "error" and not inCommand and lvl ~= "all" then
        if lvl == "none" or not important then return end
    end
    print("|TInterface\\AddOns\\OghoulesWarpath\\Media\\Gem:12:12:0:0|t |cffcdbb8eWarpath|r : " .. tostring(msg))
end

------------------------------------------------------------------
-- Etat du personnage
------------------------------------------------------------------
logById = {}            -- questID -> true (complete) / false (en cours)

function ScanLog()
    wipe(logById)
    pcall(function()
        if C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetNumQuestLogEntries then
            for i = 1, C_QuestLog.GetNumQuestLogEntries() do
                local info = C_QuestLog.GetInfo(i)
                if info and not info.isHeader and info.questID and info.questID > 0 then
                    local done = (C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID))
                        or info.isComplete == true or info.isComplete == 1
                    logById[info.questID] = done and true or false
                end
            end
        elseif GetNumQuestLogEntries then
            for i = 1, GetNumQuestLogEntries() do
                local title, _, _, isHeader, _, isComplete, _, id = GetQuestLogTitle(i)
                if title and not isHeader and id then
                    logById[id] = (isComplete == 1 or isComplete == true)
                end
            end
        end
    end)
end

function Rendue(id)
    if DB.done[id] then return true end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(id) and true or false
    end
    if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(id) and true or false end
    return false
end

function Ids(s)
    if type(s.id) == "table" then return s.id end
    return { s.id }
end

function GreenRange(lvl)
    if GetQuestGreenRange then
        local ok, r = pcall(GetQuestGreenRange)
        if ok and r then return r end
    end
    if lvl < 10 then return 5 elseif lvl < 20 then return 6 elseif lvl < 30 then return 7 end
    return 8
end

function IsGrey(s)
    if not s.lvl then return false end
    local me = UnitLevel("player")
    return s.lvl < me - GreenRange(me)
end

------------------------------------------------------------------
-- Calcul de l'etape courante
------------------------------------------------------------------
function ListHas(list, value)
    if not list then return true end
    for v in tostring(list):gmatch("[^,]+") do
        if v == value or (v == "Scourge" and value == "Undead") then return true end
    end
    return false
end

function Applies(s)
    return s and ListHas(s.class, myClass) and ListHas(s.race, myRace)
end

-- Cle d'une etape INDEPENDANTE de sa position dans le guide : type + quetes (ou empreinte du texte) + rang parmi
-- les etapes identiques. Ajouter ou retirer une etape dans une mise a jour ne decale plus ce que tu as deja vu.
do
    local sigCache = setmetatable({}, { __mode = "k" })
    local function hash(str)
        local h = 5381
        for k = 1, #str do h = (h * 33 + str:byte(k)) % 16777216 end
        return h
    end
    local function sig(s)
        local ids = s.id and table.concat(Ids(s), ",") or ""
        return (s.t or "?") .. ":" .. ids .. ":" .. tostring(s.level or "") .. ":" .. (s.id and "" or tostring(hash(s.text or "")))
    end
    function SeenKey(i)
        local list = steps
        if not (DB and DB.guide and list and list[i]) then return (DB and DB.guide or "?") .. ":" .. tostring(i) end
        local c = sigCache[list]
        if not c then
            c = {}
            local count = {}
            for j, st in ipairs(list) do
                local k = sig(st)
                count[k] = (count[k] or 0) + 1
                c[j] = "v2:" .. k .. "#" .. count[k]
            end
            sigCache[list] = c
            -- ancien format (guide:numero) : converti une fois, avec la meme correspondance qu'avant
            DB.seenV2 = DB.seenV2 or {}
            if DB.seen and not DB.seenV2[DB.guide] then
                for j = 1, #list do
                    local old = DB.guide .. ":" .. j
                    if DB.seen[old] then DB.seen[DB.guide .. ":" .. c[j]] = true; DB.seen[old] = nil end
                end
                DB.seenV2[DB.guide] = true
            end
        end
        return DB.guide .. ":" .. c[i]
    end
end

-- Etat brut d'une etape de quete, sans tenir compte de sa position dans le guide.
--   "done"    : faite (ou ignoree)
--   "todo"    : a faire maintenant (quete dans le journal, ou a prendre)
--   "absent"  : la quete n'est ni prise ni rendue (pour accept : pas encore prise)
function QuestState(s)
    local anyTodo, anyAbsent = false, false
    for _, id in ipairs(Ids(s)) do
        if DB.ignored[id] or Rendue(id) then
            -- fait
        elseif logById[id] ~= nil then
            if s.t == "accept" then
                -- prise = fait
            elseif s.t == "do" and logById[id] == true then
                -- objectifs finis = fait
            else
                anyTodo = true
            end
        else
            anyAbsent = true
        end
    end
    if anyTodo then return "todo" end
    if anyAbsent then return "absent" end
    return "done"
end

-- Renvoie "done" (faite), "skip" (sautee) ou false (a faire) pour l'etape i.
-- pendingAccept[id] = true si l'etape "Accepter" de cette quete est encore a faire.
pendingAccept = {}
computingOther = false  -- vrai pendant qu'on evalue un AUTRE guide (options, choix auto)
blockedBy = {}          -- index d'etape -> quetes prerequises manquantes (etape sautee pour ca)

function StepDone(i, anchor)
    local s = steps[i]
    if s.t == "accept" or s.t == "do" or s.t == "turnin" then
        local st = QuestState(s)
        if st == "done" then return "done" end
        if st == "todo" then return false end
        -- st == "absent" : au moins une quete ni prise ni rendue
        if s.t ~= "accept" then
            for _, id in ipairs(Ids(s)) do
                if pendingAccept[id] and not Rendue(id) and not DB.ignored[id] and logById[id] == nil then
                    return false                         -- sa prise est encore devant toi
                end
            end
            return "skip"                                -- regle 4
        end
        local skip = (i < anchor) or (IsGrey(s) and DB.guide ~= "chain") or (s.optional and DB.seen[SeenKey(i)])
            or ((s.req or 0) > (UnitLevel("player") or 60) and DB.guide ~= "chain") -- niveau requis pas atteint : impossible a prendre
            or (StyleSkip and StyleSkip(i, s))
        if not skip then
            -- prerequis : si une quete requise n'est ni rendue, ni dans le journal, ni a prendre plus haut
            -- dans le guide, cette quete ne pourra jamais etre prise -> sautee
            local blockers = {}
            for _, p in ipairs(s.preg or {}) do
                if not Rendue(p) then blockers[#blockers + 1] = p end
            end
            if s.pre then
                local ok = false
                for _, p in ipairs(s.pre) do if Rendue(p) then ok = true end end
                if not ok then for _, p in ipairs(s.pre) do blockers[#blockers + 1] = p end end
            end
            if #blockers > 0 then
                local waiting = false
                for _, p in ipairs(blockers) do
                    if logById[p] ~= nil or pendingAccept[p] then waiting = true end
                end
                if not waiting then
                    skip = true
                    if not computingOther then blockedBy[i] = blockers end
                end
            end
            -- dans un donjon, une quete dont le niveau requis est trop haut est sautee
            if IS_DUNGEON[DB.guide] and (s.req or 0) > UnitLevel("player") then skip = true end
        end
        for _, id in ipairs(Ids(s)) do
            if logById[id] == nil and not Rendue(id) and not DB.ignored[id] then
                pendingAccept[id] = not skip
            end
        end
        return skip and "skip" or false
    end
    -- entree d'un donjon : faite seulement quand tu entres vraiment dans l'instance (ou OK a la main)
    if s.t == "go" and IS_DUNGEON[DB.guide] then
        if DB.dgIn and DB.dgIn[DB.guide] then return "done" end
        return (i < anchor) and "skip" or false
    end
    if DB.seen[SeenKey(i)] then return "done" end
    if s.t == "level" and UnitLevel("player") >= (s.level or 0) then return "done" end
    if i < anchor then return "skip" end
    return false
end

-- Ancre = jusqu'ou tu es VRAIMENT rendu. On prend la derniere etape "Rendre" faite telle qu'au moins
-- la moitie des etapes "Rendre" jusque-la sont faites, et au moins 3 au total. Une quete partagee en groupe
-- ou une livraison faite en avance (isolee loin devant) ne fait donc pas tout sauter.
function FindAnchor()
    local total, done, anchor = 0, 0, 0
    for i, s in ipairs(steps) do
        if s.t == "turnin" and Applies(s) then
            total = total + 1
            local isDone = false
            for _, id in ipairs(Ids(s)) do
                if Rendue(id) and not DB.ignored[id] then isDone = true; break end
            end
            if isDone then
                done = done + 1
                if done >= 3 and done * 2 >= total then anchor = i end
            end
        end
    end
    return anchor
end

function NextApplicable(i)
    local n = #steps
    i = i + 1
    while i <= n and not Applies(steps[i]) do i = i + 1 end
    return i
end

doneCache = {}

-- Dependances et chaines de quetes (calculees une fois par guide)
depsOf = {}             -- index -> liste d'index d'etapes qui doivent etre faites avant

function AnalyzeChains()
    wipe(chainOf); wipe(depsOf)
    if not steps then return end
    local n = #steps
    -- union-find sur les QUETES, liees seulement par leurs prerequis
    local parent = {}
    local function find(x) while parent[x] ~= x do parent[x] = parent[parent[x]]; x = parent[x] end return x end
    local function union(a, b) a, b = find(a), find(b); if a ~= b then parent[b] = a end end
    local stepsOfQuest = {}
    for i = 1, n do
        local st = steps[i]
        if st.id then
            for _, id in ipairs(Ids(st)) do
                parent[id] = parent[id] or id
                stepsOfQuest[id] = stepsOfQuest[id] or {}
                table.insert(stepsOfQuest[id], i)
            end
        end
    end
    local function addDep(j, i)
        for _, d in ipairs(depsOf[j]) do if d == i then return end end
        table.insert(depsOf[j], i)
    end
    for j = 1, n do
        local st = steps[j]
        depsOf[j] = {}
        if st.id then
            for _, id in ipairs(Ids(st)) do
                for _, i in ipairs(stepsOfQuest[id]) do
                    if i < j then addDep(j, i) end
                end
            end
            if st.t == "accept" then
                local pre = {}
                for _, q in ipairs(st.preg or {}) do pre[#pre + 1] = q end
                for _, q in ipairs(st.pre or {}) do pre[#pre + 1] = q end
                for _, q in ipairs(pre) do
                    if stepsOfQuest[q] then
                        for _, i in ipairs(stepsOfQuest[q]) do
                            if i < j and steps[i].t == "turnin" then addDep(j, i) end
                        end
                        if not st.class then for _, id in ipairs(Ids(st)) do union(q, id) end end
                    end
                end
            end
        end
    end
    -- une chaine = au moins 2 quetes liees par des prerequis
    local members = {}
    for id in pairs(parent) do
        local r = find(id)
        members[r] = members[r] or {}
        table.insert(members[r], id)
    end
    local chainRoot = {}
    for r, list in pairs(members) do
        if #list >= 2 then for _, id in ipairs(list) do chainRoot[id] = r end end
    end
    local groups = {}
    for i = 1, n do
        local st = steps[i]
        if st.id then
            for _, id in ipairs(Ids(st)) do
                local r = chainRoot[id]
                if r then
                    groups[r] = groups[r] or { idx = {}, lastQ = id }
                    local g = groups[r]
                    if g.idx[#g.idx] ~= i then table.insert(g.idx, i) end
                    g.lastQ = id
                    break
                end
            end
        end
    end
    for _, g in pairs(groups) do
        local name = "?"
        local li = stepsOfQuest[g.lastQ]
        if li then
            local st = steps[li[#li]]
            for k, id in ipairs(Ids(st)) do
                if id == g.lastQ then
                    local parts = {}
                    for part in (st.quest or ""):gmatch("[^+]+") do parts[#parts + 1] = part:match("^%s*(.-)%s*$") end
                    name = parts[k] or st.quest or "?"
                end
            end
        end
        for k, i in ipairs(g.idx) do
            chainOf[i] = { name = name, qid = g.lastQ, pos = k, len = #g.idx, idx = g.idx }
        end
    end
end

function Compute()
    ScanLog()
    wipe(doneCache)
    wipe(pendingAccept)
    if not computingOther then wipe(blockedBy) end
    local n = #steps
    local anchor = FindAnchor()
    for i = 1, n do
        if Applies(steps[i]) then doneCache[i] = StepDone(i, anchor) else doneCache[i] = "skip" end
    end
    -- sortie du donjon choisie : les objectifs restants du donjon sont laisses de cote (pas ignores), on va rendre
    if IS_DUNGEON[DB.guide] and DB.dgOut and DB.dgOut[DB.guide] then
        local after = false
        for i = 1, n do
            if steps[i].t == "go" then after = true
            elseif after and steps[i].t == "do" and not doneCache[i] then doneCache[i] = "skip"
            -- quete a prendre ou a rendre a un PNJ de l'interieur (etape sans coordonnees) : impossible dehors
            elseif after and (steps[i].t == "accept" or steps[i].t == "turnin") and not steps[i].m and not doneCache[i] then
                doneCache[i] = "skip"
            elseif after and steps[i].t == "turnin" and not doneCache[i] then
                -- quete pas finie : impossible a rendre, on ne t'envoie pas au PNJ pour rien
                local ready = false
                for _, id in ipairs(Ids(steps[i])) do if logById[id] == true then ready = true end end
                if not ready then doneCache[i] = "skip" end
            end
        end
    end
    -- regle 5 : une note / optionnelle / niveau saute si l'etape suivante est deja faite
    for i = n, 1, -1 do
        local s = steps[i]
        if not doneCache[i] and (s.t == "note" or s.t == "go" or s.t == "level" or s.optional)
            and not (s.t == "go" and IS_DUNGEON[DB.guide]) then
            local j = NextApplicable(i)
            -- prise/remise facultative : les prises voisines peuvent etre faites dans un autre ordre (PNJ le plus
            -- proche d'abord), donc on regarde la prochaine etape qui n'est ni une prise ni une remise
            if s.optional and (s.t == "accept" or s.t == "turnin") then
                while j <= n and (steps[j].t == "accept" or steps[j].t == "turnin") do j = NextApplicable(j) end
            end
            if j <= n and doneCache[j] then doneCache[i] = "skip" end
        end
    end
    current = n + 1
    for i = 1, n do
        if not doneCache[i] then current = i; break end
    end
    dynOrder = nil
    if not computingOther and IS_DUNGEON_SET and IS_DUNGEON_SET[DB.guide] and OptimizeFn then
        local ok, order = pcall(OptimizeFn)
        if ok and order and order[1] then
            dynOrder = order
            -- la note d'introduction du donjon reste affichee tant que tu ne l'as pas lue
            if not (steps[current] and steps[current].t == "note") then current = order[1] end
        end
    end
    baseCurrent = current
    if not dynOrder and not computingOther and NearPick then
        local ok, j = pcall(NearPick, current)
        if ok and j then current = j end
    end
    if computingOther then return end
    if focus and (doneCache[focus] or not steps[focus]) then focus = nil end
    DB.step[DB.guide] = current
end
