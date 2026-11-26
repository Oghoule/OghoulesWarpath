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
-- v1.50 : etat partage du guide (etape courante, etapes, apercu, cible de la fleche...).
-- Les fichiers le lisent par State.x ; ns.CoreEnv redirige encore les anciens noms (tests).
ns.State = ns.State or {}
local State = ns.State
-- Environnement prive partage par tous les fichiers du moteur (Core, Route, Estimate, Skin, Flow, Window,
-- Comfort, Commands, Events) : leurs variables communes y vivent, les vraies globales du jeu restent dans _G.
local DECL = {}
for n in ("heldNear WeaveSteps PerfOn RetargetLight TrailTick TrailPoint PassageFor HearthButton HEAD_H OnTheWay IsCaveStep CaveTrack StepPoint DungeonQuests nearKind NearPick NearTick ThenLine DungeonInstanceMatches DL CheckZoneLevel CheckProfIntro ProfDetect CheckProfQuests DungeonReq Tip Popup HearthPos Advice currentAdvice RefreshInner SuggestDungeonForLevel styleCache CheckClassQuests AskChain BestFlight CLASSBIT CheckDungeons ClearWaypoint Compute D DB Estimate KnownFlights Lang LearnGates LockCandidates MyChain OnEvent UpdateMini QMCandidates QMSkip QMClosePick QMGo CheckDungeonLeft HearthPlace CityCavePoint POPUP_HEAD OptimizeFn PlaceNative PlayerPos PlayerWP Refresh Rendue ScanLog SetGuide SetWaypoint Short StepDone T TransportFor TravelCost UpdateDistance W WP Walk desiredWP distTarget dynOrder errShown f lastKill say wpCache"):gmatch("%S+") do DECL[n] = true end
-- v1.50 : anciens noms de l'etat, rediriges vers State (outils de test, oubli eventuel) ; jamais stockes dans env
local STATE = {}
for n in ("tomtomWP lastWP baseCurrent current focus flightPlan pending G steps peek doneCache pendingAccept computingOther asking inCommand myClass myRace"):gmatch("%S+") do STATE[n] = true end
local assigned = {}
-- v1.50 : noms publies par les modules (ns.Mod, Core/Modules.lua) : retrouves pour les anciens acces par CoreEnv
local MODIDX = ns.ModIndex or {}
local env = setmetatable({}, {
    __index = function(_, k)
        if STATE[k] then return State[k] end
        if DECL[k] then if assigned[k] then return nil end return _G[k] end
        local m = MODIDX[k]
        if m then return m[k] end
        return _G[k]
    end,
    __newindex = function(t, k, v)
        if STATE[k] then State[k] = v
        elseif DECL[k] then assigned[k] = true; rawset(t, k, v)
        elseif MODIDX[k] then MODIDX[k][k] = v
        else _G[k] = v end
    end,
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
        for _, m in ipairs(blocked) do DEFAULT_CHAT_FRAME:AddMessage("|TInterface\\AddOns\\OghoulesWarpath\\Media\\Gem:12:12:0:0|t |cffcdbb8eWarpath|r : |cffc24a3e" .. ((Lang and Lang() == "en") and "action blocked by the game" or "action bloquée par le jeu") .. "|r : " .. m) end
        wipe(blocked)
    end
    fr:SetScript("OnEvent", function(_, event, who, fn)
        if event == "PLAYER_ENTERING_WORLD" then flush(); return end
        if who == ADDON then
            local m = tostring(fn) .. " (" .. event .. ")"
            -- securite : l'automatisation qui vient d'agir est coupee pour ne plus jamais declencher le blocage
            local lt = ns.lastTrace
            local OFF = { AcceptQuest = "autoQuest", CompleteQuest = "autoQuest", GetQuestReward = "autoQuest",
                          Gossip = "autoQuest", TakeTaxiNode = "flyAuto", ["bouton d'objet (creation)"] = "itemBtn", ["bouton d'objet (objet)"] = "itemBtn" }
            if lt and GetTime and GetTime() - lt[2] < 2 and OFF[lt[1]] and WarpathCharDB then
                WarpathCharDB[OFF[lt[1]]] = false
                m = m .. "  ->  " .. lt[1] .. " : fonction interdite par Forever, désactivée automatiquement (Options)"
            end
            blocked[#blocked + 1] = m
            -- v1.46 : contexte (combat, mort, carte ouverte, dernier appel sensible) pour trouver la cause
            local ctx = {}
            pcall(function()
                if InCombatLockdown and InCombatLockdown() then ctx[#ctx + 1] = "combat" end
                if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then ctx[#ctx + 1] = "mort" end
                if WorldMapFrame and WorldMapFrame:IsShown() then ctx[#ctx + 1] = "carte" end
                if C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint and C_SuperTrack.IsSuperTrackingUserWaypoint() then ctx[#ctx + 1] = "suivi" end
                if lt and GetTime then ctx[#ctx + 1] = string.format("%s il y a %.0f s", tostring(lt[1]), GetTime() - lt[2]) end
            end)
            local full = #ctx > 0 and (m .. " [" .. table.concat(ctx, ", ") .. "]") or m
            -- v1.42 : gardee dans les sauvegardes du compte (SavedVariables du .toc) pour les diagnostics, 50 dernieres
            WarpathBlockedLog = WarpathBlockedLog or {}
            table.insert(WarpathBlockedLog, date and (date("%Y-%m-%d %H:%M:%S") .. " " .. full) or full)
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
        -- v1.47 : un seul vecteur reutilise (CreateVector2D recopie toutes les fonctions du mixin : ~2 Ko a chaque
        -- appel, des dizaines de fois par seconde ; mesure /warpath perf du 2026-11-25)
        local v = ns.MapAPI.vec
        if not v then v = CreateVector2D(x, y); ns.MapAPI.vec = v
        elseif v.SetXY then v:SetXY(x, y) else v.x, v.y = x, y end
        return C_Map.GetWorldPosFromMapPos(mapID, v)
    end,
}
local _ENV = env
if setfenv then setfenv(1, env) end
-- v1.50 : module ns.Mod.Core (publie en fin de fichier pour les autres fichiers)
local AnalyzeChains, Applies, CHAIN, CHECK, DUNGEONS, FindAnchor, GreenRange, Guides, ICON, IS_DUNGEON, Ids
local IsGrey, ListHas, MAIN_ORDER, MAXLVL, MINLVL, NearNpc, NextApplicable, QName, QuestTitle, SeenKey
local StepText, Title, VERSION, blockedBy, chainOf, depsOf, logById
local Comfort = ns.Mod.Comfort -- v1.50 : module
local Route = ns.Mod.Route -- v1.50 : module
-- v1.50 : noms propres a ce fichier (sortis de DECL, Core.lua)
local DOT, HOLD_R, IS_DUNGEON_SET, LANG, QuestState, heldPrev
Guides = ns.Guides or {}

DB = nil -- WarpathCharDB (par personnage)
f = nil -- fenetre principale
State.G, State.steps = nil, nil -- guide actif et ses etapes
State.myClass, State.myRace = nil, nil
State.current = 1             -- etape calculee
State.peek = nil -- etape regardee avec < > (apercu), nil sinon
State.focus = nil -- etape choisie en cliquant (liste "A suivre" ou debut de chaine)
dynOrder = nil -- ordre optimise des etapes de ramassage (donjons), ou nil
chainOf = {}            -- index d'etape -> { name, pos, len, first = index de la 1re etape }
OptimizeFn = nil -- defini plus bas (besoin des fonctions de carte)
State.flightPlan = nil -- vol conseille en ce moment ({ from, to }) pour surligner la destination
State.lastWP, State.tomtomWP = nil, nil
State.pending = false

D = ns.Data
CHAIN, MAXLVL, DUNGEONS, IS_DUNGEON = D.CHAIN, D.MAXLVL, D.DUNGEONS, D.IS_DUNGEON
IS_DUNGEON_SET = IS_DUNGEON

ICON = "Interface\\AddOns\\OghoulesWarpath\\Media\\Warpath64"
VERSION = "1.50"
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
State.inCommand = false
function say(msg, important)
    local lvl = DB and DB.chatLevel or "all"
    if important ~= "error" and not State.inCommand and lvl ~= "all" then
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
    return s and ListHas(s.class, State.myClass) and ListHas(s.race, State.myRace)
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
        local list = State.steps
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
State.pendingAccept = {}
State.computingOther = false  -- vrai pendant qu'on evalue un AUTRE guide (options, choix auto)
blockedBy = {}          -- index d'etape -> quetes prerequises manquantes (etape sautee pour ca)
-- v1.49 : prises laissees derriere toi (voir StepDone) : index -> true si tu es pres de leur PNJ.
-- NearTick refait le calcul quand tu t'en approches ou t'en eloignes.
heldNear, heldPrev = {}, {}
HOLD_R = 80             -- metres : meme camp (comme HUB_R dans Near.lua)
function NearNpc(s, wasNear)
    if State.computingOther or not (s and s.m and s.x and PlayerWP and WP) then return false end
    local me = PlayerWP(); if not me then return false end
    local g = WP(s.m, s.x, s.y)
    if not (g and g[3] == me[3]) then return false end
    -- un peu plus large pour sortir que pour entrer : pas de va-et-vient a la limite
    return Route.Dist(me[1], me[2], g[1], g[2]) < (wasNear and HOLD_R + 20 or HOLD_R)
end
-- deux etapes au meme camp (PNJ a moins de HOLD_R l'un de l'autre, meme continent)
local function SameCamp(a, b)
    if not (a and b and a.m and a.x and b.m and b.x and WP) then return false end
    local p, q = WP(a.m, a.x, a.y), WP(b.m, b.x, b.y)
    return p and q and p[3] == q[3] and Route.Dist(p[1], p[2], q[1], q[2]) < HOLD_R or false
end

function StepDone(i, anchor)
    local s = State.steps[i]
    if s.t == "accept" or s.t == "do" or s.t == "turnin" then
        local st = QuestState(s)
        if st == "done" then return "done" end
        if st == "todo" then return false end
        -- st == "absent" : au moins une quete ni prise ni rendue
        if s.t ~= "accept" then
            for _, id in ipairs(Ids(s)) do
                if State.pendingAccept[id] and not Rendue(id) and not DB.ignored[id] and logById[id] == nil then
                    return false                         -- sa prise est encore devant toi
                end
            end
            return "skip"                                -- regle 4
        end
        -- v1.47 : etape d'une chaine integree (woven) : choisie par toi, traitee comme dans le guide « chain »
        -- (ni ancre, ni quete grise, ni style de jeu)
        local chainLike = DB.guide == "chain" or s.woven
        local lvlOk = (s.req or 0) <= (UnitLevel("player") or 60) or chainLike
        -- v1.49 : prise laissee derriere toi -- avant l'ancre (le guide t'a fait rendre une quete plus loin
        -- d'abord), ou niveau requis atteint seulement apres l'avoir depassee (DB.lvlWait, voir Compute).
        -- Elle reste proposee tant que tu es pres de son PNJ (meme camp), mais le guide ne te fait plus
        -- revenir en arriere pour elle. Donjons et chaines : comportement d'avant.
        local waitLvl = lvlOk and not s.woven and DB.lvlWait and DB.lvlWait[SeenKey(i)] and true or false
        local passed = (i < anchor and not s.woven) or waitLvl
        local near = false
        if passed and not s.optional and not IS_DUNGEON[DB.guide] and DB.guide ~= "chain"   -- optionnelle : comme avant
            and (waitLvl or SameCamp(s, State.steps[anchor])) then   -- avant l'ancre : seulement le camp de l'ancre
            near = NearNpc(s, heldPrev[i])
            if not State.computingOther then heldNear[i] = near end
        end
        local skip = (passed and not near) or (IsGrey(s) and not chainLike) or (s.optional and DB.seen[SeenKey(i)])
            or not lvlOk -- niveau requis pas atteint : impossible a prendre
            or (Comfort.StyleSkip and not s.woven and Comfort.StyleSkip(i, s))
            -- v1.45 : quete d'appel (bc = quete visee) : le jeu ne la propose plus si la quete visee est
            -- dans ton journal ou deja rendue (Tsunaman sans Trouble in the Deeps, 2026-11-23)
            or (s.bc and (logById[s.bc] ~= nil or Rendue(s.bc)))
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
                    if logById[p] ~= nil or State.pendingAccept[p] then waiting = true end
                end
                if not waiting then
                    skip = true
                    if not State.computingOther then blockedBy[i] = blockers end
                end
            end
            -- dans un donjon, une quete dont le niveau requis est trop haut est sautee
            if IS_DUNGEON[DB.guide] and (s.req or 0) > UnitLevel("player") then skip = true end
        end
        for _, id in ipairs(Ids(s)) do
            if logById[id] == nil and not Rendue(id) and not DB.ignored[id] then
                State.pendingAccept[id] = not skip
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
    for i, s in ipairs(State.steps) do
        -- v1.47 : les « Rendre » d'une chaine integree ne comptent pas (rendue tot, elle ferait tout sauter)
        if s.t == "turnin" and Applies(s) and not s.woven then
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
    local n = #State.steps
    i = i + 1
    while i <= n and not Applies(State.steps[i]) do i = i + 1 end
    return i
end

State.doneCache = {}

-- Dependances et chaines de quetes (calculees une fois par guide)
depsOf = {}             -- index -> liste d'index d'etapes qui doivent etre faites avant

function AnalyzeChains()
    wipe(chainOf); wipe(depsOf)
    if not State.steps then return end
    local n = #State.steps
    -- union-find sur les QUETES, liees seulement par leurs prerequis
    local parent = {}
    local function find(x) while parent[x] ~= x do parent[x] = parent[parent[x]]; x = parent[x] end return x end
    local function union(a, b) a, b = find(a), find(b); if a ~= b then parent[b] = a end end
    local stepsOfQuest = {}
    for i = 1, n do
        local st = State.steps[i]
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
        local st = State.steps[j]
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
                            if i < j and State.steps[i].t == "turnin" then addDep(j, i) end
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
        local st = State.steps[i]
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
            local st = State.steps[li[#li]]
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
    wipe(State.doneCache)
    wipe(State.pendingAccept)
    if not State.computingOther then wipe(blockedBy) end
    local n = #State.steps
    local anchor = FindAnchor()
    if not State.computingOther then heldPrev, heldNear = heldNear, {} end
    for i = 1, n do
        if Applies(State.steps[i]) then State.doneCache[i] = StepDone(i, anchor) else State.doneCache[i] = "skip" end
    end
    -- sortie du donjon choisie : les objectifs restants du donjon sont laisses de cote (pas ignores), on va rendre
    if IS_DUNGEON[DB.guide] and DB.dgOut and DB.dgOut[DB.guide] then
        local after = false
        for i = 1, n do
            if State.steps[i].t == "go" then after = true
            elseif after and State.steps[i].t == "do" and not State.doneCache[i] then State.doneCache[i] = "skip"
            -- quete a prendre ou a rendre a un PNJ de l'interieur (etape sans coordonnees) : impossible dehors
            elseif after and (State.steps[i].t == "accept" or State.steps[i].t == "turnin") and not State.steps[i].m and not State.doneCache[i] then
                State.doneCache[i] = "skip"
            elseif after and State.steps[i].t == "turnin" and not State.doneCache[i] then
                -- quete pas finie : impossible a rendre, on ne t'envoie pas au PNJ pour rien
                local ready = false
                for _, id in ipairs(Ids(State.steps[i])) do if logById[id] == true then ready = true end end
                if not ready then State.doneCache[i] = "skip" end
            end
        end
    end
    -- regle 5 : une note / optionnelle / niveau saute si l'etape suivante est deja faite
    for i = n, 1, -1 do
        local s = State.steps[i]
        if not State.doneCache[i] and (s.t == "note" or s.t == "go" or s.t == "level" or s.optional)
            and not (s.t == "go" and IS_DUNGEON[DB.guide]) then
            local j = NextApplicable(i)
            -- prise/remise facultative : les prises voisines peuvent etre faites dans un autre ordre (PNJ le plus
            -- proche d'abord), donc on regarde la prochaine etape qui n'est ni une prise ni une remise
            if s.optional and (s.t == "accept" or s.t == "turnin") then
                while j <= n and (State.steps[j].t == "accept" or State.steps[j].t == "turnin") do j = NextApplicable(j) end
            end
            if j <= n and State.doneCache[j] then State.doneCache[i] = "skip" end
        end
    end
    State.current = n + 1
    for i = 1, n do
        if not State.doneCache[i] then State.current = i; break end
    end
    -- v1.49 : prises depassees faute de niveau pendant que tu avancais dans la zone. Quand le niveau arrive,
    -- elles ne te font pas revenir en arriere (StepDone) : proposees seulement en repassant pres de leur PNJ.
    -- Pas si tu n'as encore rien fait dans le guide (zone ouverte trop tot), ni avant une etape "Monte au
    -- niveau X" (la, le guide veut justement que tu reviennes les prendre), ni pour une quete qui en
    -- debloque une autre (QuestUnlocks : sinon toute la suite serait perdue).
    if not State.computingOther and not IS_DUNGEON[DB.guide] and DB.guide ~= "chain" and State.current <= n
        and State.steps[State.current].t ~= "level" then
        local first
        for i = 1, State.current - 1 do
            local s = State.steps[i]
            if (s.t == "accept" or s.t == "do" or s.t == "turnin") and State.doneCache[i] == "done" and s.id and Applies(s) and not s.woven then
                local real = false
                for _, id in ipairs(Ids(s)) do if not DB.ignored[id] then real = true end end
                if real then first = i; break end
            end
        end
        local lvl = UnitLevel("player") or 60
        for i = State.current - 1, (first or State.current) + 1, -1 do
            local s = State.steps[i]
            if s.t == "level" then break end
            if s.t == "accept" and not s.woven and (s.req or 0) > lvl and State.doneCache[i] == "skip" and Applies(s) then
                local key = SeenKey(i)
                if not (DB.lvlWait and DB.lvlWait[key]) then
                    local unlocks = false
                    for _, id in ipairs(Ids(s)) do if Comfort.QuestUnlocks and Comfort.QuestUnlocks(id) then unlocks = true end end
                    if not unlocks then DB.lvlWait = DB.lvlWait or {}; DB.lvlWait[key] = true end
                end
            end
        end
    end
    dynOrder = nil
    if not State.computingOther and IS_DUNGEON_SET and IS_DUNGEON_SET[DB.guide] and OptimizeFn then
        local ok, order = pcall(OptimizeFn)
        if ok and order and order[1] then
            dynOrder = order
            -- la note d'introduction du donjon reste affichee tant que tu ne l'as pas lue
            if not (State.steps[State.current] and State.steps[State.current].t == "note") then State.current = order[1] end
        end
    end
    State.baseCurrent = State.current
    if not dynOrder and not State.computingOther and NearPick then
        local ok, j = pcall(NearPick, State.current)
        if ok and j then State.current = j end
    end
    if State.computingOther then return end
    if State.focus and (State.doneCache[State.focus] or not State.steps[State.focus]) then State.focus = nil end
    DB.step[DB.guide] = State.current
end

-- v1.50 : ce que ce fichier offre aux autres (ns.Mod.Core)
do
    local M = ns.Mod.Core
    M.AnalyzeChains = AnalyzeChains
    M.Applies = Applies
    M.CHAIN = CHAIN
    M.CHECK = CHECK
    M.DUNGEONS = DUNGEONS
    M.FindAnchor = FindAnchor
    M.GreenRange = GreenRange
    M.Guides = Guides
    M.ICON = ICON
    M.IS_DUNGEON = IS_DUNGEON
    M.Ids = Ids
    M.IsGrey = IsGrey
    M.ListHas = ListHas
    M.MAIN_ORDER = MAIN_ORDER
    M.MAXLVL = MAXLVL
    M.MINLVL = MINLVL
    M.NearNpc = NearNpc
    M.NextApplicable = NextApplicable
    M.QName = QName
    M.QuestTitle = QuestTitle
    M.SeenKey = SeenKey
    M.StepText = StepText
    M.Title = Title
    M.VERSION = VERSION
    M.blockedBy = blockedBy
    M.chainOf = chainOf
    M.depsOf = depsOf
    M.logById = logById
end
