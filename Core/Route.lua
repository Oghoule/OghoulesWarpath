-- Oghoule's Warpath : moteur (Route.lua) - voir Core.lua
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end
-- v1.50 : etat partage du guide (Core.lua, ns.State)
local State = ns.State
local Core = ns.Mod.Core -- v1.50 : module
local Flow = ns.Mod.Flow -- v1.50 : module
local Est = ns.Mod.Est -- v1.50 : module
-- v1.50 : module ns.Mod.Route (publie en fin de fichier pour les autres fichiers)
local Continent, Dist, FLIGHTS, GATES, LearnFlightHere, PCOL, PREFIX, PrereqDetour, TRANSPORTS, WorldPos
local ZoneOf, band, optCache
-- v1.50 : noms propres a ce fichier (sortis de DECL, Core.lua)
local BlizzArrowShown, CONT_FALLBACK, CanFly, EK, FLY_FACTOR, FLY_OVERHEAD, GateNodes, KALIMDOR, RIDE, UNKNOWN
local WIND, gateKey, gateNodes, lastSample, walkCache

------------------------------------------------------------------
-- Waypoints (natif si possible, TomTom si installe)
------------------------------------------------------------------
desiredWP = nil -- waypoint voulu par le guide (on le remet si le jeu l'efface a l'arrivee)

-- Repere du jeu jamais touche en combat : poser/effacer le repere fait redessiner les epingles de la
-- carte par le code du jeu « au nom » de Warpath, et SetPassThroughButtons est alors bloque (rapport du
-- 2026-11-23, 50 blocages pendant des escortes). On attend la fin du combat.
local nativePending = false
local function InFight() return InCombatLockdown and InCombatLockdown() end
do
    local fr = CreateFrame("Frame")
    fr:RegisterEvent("PLAYER_REGEN_ENABLED")
    fr:SetScript("OnEvent", function()
        if not nativePending then return end
        nativePending = false
        if desiredWP then PlaceNative(desiredWP)
        elseif C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
    end)
end

function ClearWaypoint()
    desiredWP = nil
    if InFight() then nativePending = true
    elseif C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
    if State.tomtomWP and TomTom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, State.tomtomWP) end
    State.tomtomWP = nil
end

-- Avec la fleche Warpath, on garde le repere du jeu (point jaune, icone sur la minicarte), mais on
-- cache la fleche "Map Pin" de l'addon FojjiCore (FojjiCoreWaypointArrow) pour ne pas en avoir deux.
local foreignHide, foreignHooked = false, false
local function HideForeignArrow()
    local f = _G.FojjiCoreWaypointArrow
    if not f then return end
    if not foreignHooked and f.HookScript then
        foreignHooked = true
        f:HookScript("OnShow", function(self) if foreignHide then self:Hide() end end)
    end
    if foreignHide and f:IsShown() then f:Hide() end
end

function BlizzArrowShown(show)
    foreignHide = not show
    -- FojjiCore cree sa fleche un peu apres la pose du repere : on repasse quelques fois
    if C_Timer and C_Timer.After then
        for _, d in ipairs({ 0.3, 1.5, 4 }) do C_Timer.After(d, function() pcall(HideForeignArrow) end) end
    else pcall(HideForeignArrow) end
end

function PlaceNative(w)
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return end
    if InFight() then nativePending = true; return end -- pose a la fin du combat (voir plus haut)
    -- repere du jeu decoche (avec la fleche Warpath) : pas de point jaune ni d'icone du jeu sur la minicarte
    if DB.ownArrow ~= false and DB.gameWP == false then
        pcall(function()
            if C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() then C_Map.ClearUserWaypoint() end
        end)
        return
    end
    pcall(function()
        if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(w.m) then return end
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(w.m, w.x / 100, w.y / 100))
        -- v1.46 : « suivi » du repere seulement si tu utilises la fleche du jeu. Le suivi fait redessiner par
        -- Warpath les icones de quete (suivi des objectifs, carte) ; elles restent « marquees » et, plus tard en
        -- combat, le jeu bloque SetPassThroughButtons quand il les met a jour (rapports des 23 et 24 novembre :
        -- escortes, Durnholde, 14 boutons d'un coup alors que le repere n'est plus touche en combat).
        if DB.ownArrow == false and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
        BlizzArrowShown(DB.ownArrow == false)
    end)
end

function SetWaypoint(s)
    ClearWaypoint()
    if not DB.wp or not s or not s.x or not s.y then return end
    local mapID = s.m
    if not mapID and C_Map and C_Map.GetBestMapForUnit then mapID = C_Map.GetBestMapForUnit("player") end
    if not mapID then return end
    desiredWP = { m = mapID, x = s.x, y = s.y, title = s.quest or s.text }
    if TomTom and TomTom.AddWaypoint then
        pcall(function()
            -- cleardistance = 0 : TomTom ne supprime pas la fleche quand on arrive
            State.tomtomWP = TomTom:AddWaypoint(mapID, s.x / 100, s.y / 100,
                { title = desiredWP.title, persistent = false, minimap = true, world = true, cleardistance = 0, crazy = (DB.ownArrow == false) })
        end)
    end
    PlaceNative(desiredWP)
end

------------------------------------------------------------------
-- Affichage
------------------------------------------------------------------
PCOL = { accept = "d6b866", ["do"] = "d69a66", turnin = "9cc7a8", go = "cdbb8e", note = "b5aa98", level = "d6b866" }
PREFIX = setmetatable({}, { __index = function(_, k)
    if not PCOL[k] then return nil end
    return "|cff" .. PCOL[k] .. T(k) .. "|r"
end })

function Short(s)
    return (PREFIX[s.t] or "") .. " " .. (Core.QName(s) or Core.StepText(s):sub(1, 45))
end

------------------------------------------------------------------
-- Changement de continent : zeppelins / bateau les plus rapides
------------------------------------------------------------------
KALIMDOR, EK, CONT_FALLBACK, TRANSPORTS = D.KALIMDOR, D.EK, D.CONT_FALLBACK, D.TRANSPORTS

-- v1.47 : le continent d'une carte ne change pas : on le retient (avant, chaque appel creait une fiche de carte
-- par niveau, des dizaines de fois par seconde via PlayerWP ; mesure /warpath perf du 2026-11-25)
local contCache = {}
function Continent(mapID)
    if not mapID then return nil end
    local c = contCache[mapID]
    if c ~= nil then return c or nil end
    local sure = false   -- vrai seulement si le jeu a repondu pour toute la chaine (pas au chargement, ni dans les tests)
    if C_Map and C_Map.GetMapInfo then
        local m, guard = mapID, 0
        sure = true
        while m and m > 0 and guard < 10 do
            local info = C_Map.GetMapInfo(m)
            if not info then sure = false; break end
            if info.mapType == 2 then contCache[mapID] = m; return m end      -- Enum.UIMapType.Continent
            m, guard = info.parentMapID, guard + 1
        end
    end
    c = CONT_FALLBACK[mapID]
    if sure then contCache[mapID] = c or false end
    return c
end

function WorldPos(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, _, v = pcall(ns.MapAPI.WorldFromMap, mapID, x / 100, y / 100)
    if ok and v then return v.x, v.y end
end

-- v1.47 : ta position est calculee une seule fois par image (GetTime ne change pas pendant une image) : la fleche,
-- l'icone de la minicarte, la petite fleche et la distance la demandaient chacune (mesure /warpath perf du 2026-11-25)
-- (pas en simulation : l'horloge des tests reste fixe pendant qu'ils deplacent le joueur)
local ppT, ppM, ppX, ppY
function PlayerPos()
    local now = not WARPATH_TEST and GetTime and GetTime()
    if now and now == ppT then return ppM, ppX, ppY end
    ppT, ppM, ppX, ppY = now, nil, nil, nil
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local m = C_Map.GetBestMapForUnit("player")
    if not m then return nil end
    ppM = m
    local okp, p = pcall(ns.MapAPI.PlayerPos, m, "player")
    if not okp then p = nil end
    if p then
        local x, y = p:GetXY()
        if x and (x > 0 or y > 0) then ppX, ppY = x * 100, y * 100; return m, ppX, ppY end
    end
    return m
end

function Dist(ax, ay, bx, by)
    if not (ax and bx) then return nil end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- Renvoie le transport a prendre pour atteindre l'etape s, ou nil si tu es deja sur le bon continent.
function TransportFor(s)
    if not (s and s.m and s.x) then return nil end
    local pm, px, py = PlayerPos()
    local here, there = Continent(pm), Continent(s.m)
    if not here or not there or here == there then return nil end
    local pwx, pwy
    if px then pwx, pwy = WorldPos(pm, px, py) end
    local twx, twy = WorldPos(s.m, s.x, s.y)
    local best, bestCost
    for prio, tr in ipairs(TRANSPORTS) do
        if Continent(tr.from[1]) == here and Continent(tr.to[1]) == there then
            local fx, fy = WorldPos(tr.from[1], tr.from[2], tr.from[3])
            local ax, ay = WorldPos(tr.to[1], tr.to[2], tr.to[3])
            local d1, d2 = Dist(pwx, pwy, fx, fy), Dist(ax, ay, twx, twy)
            -- sans coordonnees monde : l'ordre de la liste sert de priorite (zeppelin UC/Orgrimmar d'abord)
            local cost = (d1 and d2) and (d1 + d2 + (tr.kind == "boat" and 400 or 0))
                or (prio - (tr.from[1] == pm and 100 or 0))   -- sans coordonnees monde : depart dans ta zone d'abord
            if not bestCost or cost < bestCost then best, bestCost = tr, cost end
        end
    end
    return best
end

-- Cout d'un trajet (en "metres"), en tenant compte des zeppelins / bateau si on change de continent.
RIDE = 1500                     -- equivalent distance d'un trajet en zeppelin/bateau (attente comprise)
wpCache = {}
function WP(m, x, y)
    local k = m .. ":" .. x .. ":" .. y
    local v = wpCache[k]
    if v == nil then
        local wx, wy = WorldPos(m, x, y)
        v = wx and { wx, wy, Continent(m), m } or false
        wpCache[k] = v
    end
    return v or nil
end

FLIGHTS = D.FLIGHTS
FLY_FACTOR, FLY_OVERHEAD = 0.3, 150   -- un vol ~3x plus rapide qu'a pied, + temps de decollage/atterrissage

-- (meme cache par image ; une nouvelle table a chaque image, jamais modifiee ensuite : certains la gardent, ex. FlightRecheck)
local pwT, pwV
function PlayerWP()
    local now = not WARPATH_TEST and GetTime and GetTime()
    if now and now == pwT then return pwV end
    pwT, pwV = now, nil
    local pm, px, py = PlayerPos()
    if not (pm and px) then return nil end
    local wx, wy = WorldPos(pm, px, py)
    pwV = wx and { wx, wy, Continent(pm), pm } or nil
    return pwV
end

------------------------------------------------------------------
-- Trajet a pied realiste : les zones ne communiquent que par leurs passages (graphe + Dijkstra).
-- Les passages connus sont dans Data.lua ; ceux que tu traverses sont appris (DB.gates).
------------------------------------------------------------------
GATES = D.GATES or {}
WIND, UNKNOWN = 1.15, 1.35          -- detours d'un chemin reel / zone sans passage connu
-- v1.47 : la zone d'une carte ne change pas : on la retient (Walk l'appelait deux fois par calcul, des milliers
-- de fois par seconde chez un joueur a 18 points de vol ; mesure /warpath perf du 2026-11-25)
local zoneCache = {}
function ZoneOf(m)
    if not m then return nil end
    local z = zoneCache[m]
    if z then return z end
    local sure = false   -- vrai seulement si le jeu a repondu pour toute la chaine (pas au chargement)
    if C_Map and C_Map.GetMapInfo then
        local cur, guard = m, 0
        sure = true
        while cur and cur > 0 and guard < 6 do
            local info = C_Map.GetMapInfo(cur)
            if not info then sure = false; break end
            if (info.mapType or 3) <= 3 then zoneCache[m] = cur; return cur end
            cur, guard = info.parentMapID, guard + 1
        end
    end
    if sure then zoneCache[m] = m end
    return m
end

gateNodes, gateKey = nil, nil
walkCache = {}
function GateNodes()
    local learned = DB and DB.gates
    local key = learned and #learned or 0
    if gateNodes and gateKey == key then return gateNodes end
    local list = {}
    for _, g in ipairs(GATES) do
        local w = WP(g.m, g.x, g.y)
        if w then list[#list + 1] = { w[1], w[2], w[3], z1 = g.z[1], z2 = g.z[2], c = g.cost or 0 } end
    end
    for _, g in ipairs(learned or {}) do
        list[#list + 1] = { g[1], g[2], g[3], z1 = g[4], z2 = g[5], c = g[6] or 0 }
    end
    gateNodes, gateKey = list, key
    wipe(walkCache)
    return list
end

function Walk(a, b)
    if not (a and b) or a[3] ~= b[3] then return nil end
    local d = Dist(a[1], a[2], b[1], b[2])
    local za, zb = ZoneOf(a[4]), ZoneOf(b[4])
    if not za or not zb or za == zb then return d * WIND end
    local gates = GateNodes()                -- (avant la cle : vide walkCache si les passages ont change)
    local ck = za .. ">" .. zb .. ":" .. math.floor(a[1] / 50) .. ":" .. math.floor(a[2] / 50) .. ":"
        .. math.floor(b[1] / 50) .. ":" .. math.floor(b[2] / 50)
    if walkCache[ck] then return walkCache[ck] end
    -- v1.47 : la liste des passages n'est preparee qu'en cas de calcul (avant : a chaque appel, meme en cache)
    local nodes = {}
    for _, g in ipairs(gates) do if g[3] == a[3] then nodes[#nodes + 1] = g end end
    local dist, done, best = {}, {}, nil
    for k, g in ipairs(nodes) do
        if g.z1 == za or g.z2 == za then dist[k] = Dist(a[1], a[2], g[1], g[2]) * WIND + g.c end
    end
    while true do
        local u, du
        for k, v in pairs(dist) do if not done[k] and (not du or v < du) then u, du = k, v end end
        if not u or (best and du >= best) then break end
        done[u] = true
        local g = nodes[u]
        if g.z1 == zb or g.z2 == zb then
            local c = du + Dist(g[1], g[2], b[1], b[2]) * WIND
            if not best or c < best then best = c end
        end
        for k, h in ipairs(nodes) do
            if not done[k] and (h.z1 == g.z1 or h.z1 == g.z2 or h.z2 == g.z1 or h.z2 == g.z2) then
                local c = du + Dist(g[1], g[2], h[1], h[2]) * WIND + h.c
                if not dist[k] or c < dist[k] then dist[k] = c end
            end
        end
    end
    local v = best or d * UNKNOWN
    walkCache[ck] = v
    return v
end

-- Apprend un passage quand tu changes de zone a pied (pas en vol, pas de teleportation).
lastSample = nil
function LearnGates()
    local here = PlayerWP()
    if not here then lastSample = nil; return end
    local z = ZoneOf(here[4])
    if lastSample and lastSample.z ~= z and lastSample.w[3] == here[3] and not (UnitOnTaxi and UnitOnTaxi("player"))
        and Dist(lastSample.w[1], lastSample.w[2], here[1], here[2]) < 60 then
        DB.gates = DB.gates or {}
        local mx, my = (lastSample.w[1] + here[1]) / 2, (lastSample.w[2] + here[2]) / 2
        local dup = false
        for _, g in ipairs(DB.gates) do
            if ((g[4] == lastSample.z and g[5] == z) or (g[4] == z and g[5] == lastSample.z)) and Dist(g[1], g[2], mx, my) < 80 then dup = true end
        end
        if not dup and #DB.gates < 200 then DB.gates[#DB.gates + 1] = { mx, my, here[3], lastSample.z, z } end
    end
    lastSample = { w = here, z = z }
end

-- Peut-on voler de A vers B ? Si on a deja ouvert la carte de vol en A, on connait la liste exacte
-- des destinations atteignables (correspondances comprises). Sinon on suppose que oui.
-- v1.43 : la liste de A ne bloque B que si B etait deja connu quand on l'a enregistree (fpLinksKnown).
-- Un point appris plus tard, ou une liste ancienne sans cet instantane, ne bloque plus rien.
function CanFly(aKey, bKey)
    local links = DB and DB.fpLinks and DB.fpLinks[aKey]
    if not links or links[bKey] then return true end
    local knownThen = DB.fpLinksKnown and DB.fpLinksKnown[aKey]
    if not knownThen then return true end
    return not knownThen[bKey]
end

function KnownFlights()
    local list = {}
    if not DB or not DB.fp then return list end
    for _, n in ipairs(FLIGHTS) do
        if DB.fp[n.key] then
            local w = WP(n.m, n.x, n.y)
            if w then list[#list + 1] = { node = n, w = w } end
        end
    end
    return list
end

-- Nouveau point de vol decouvert (message du jeu) : on note le maitre de vol le plus proche,
-- sans attendre que tu ouvres la carte des vols (v1.39).
function LearnFlightHere()
    local here = PlayerWP()
    if not (here and DB) then return end
    local best, bd
    for _, n in ipairs(FLIGHTS) do
        local w = WP(n.m, n.x, n.y)
        if w and w[3] == here[3] then
            local d = Dist(here[1], here[2], w[1], w[2])
            if not bd or d < bd then best, bd = n, d end
        end
    end
    if best and bd < 100 then
        DB.fp = DB.fp or {}
        if not DB.fp[best.key] then
            DB.fp[best.key] = true
            -- v1.43 : tes points connus d'un meme continent sont relies ; on ajoute le nouveau point
            -- aux liaisons deja notees sur ce continent, sans attendre de rouvrir chaque carte des vols.
            local bw = WP(best.m, best.x, best.y)
            for _, n in ipairs(FLIGHTS) do
                local links = DB.fpLinks and DB.fpLinks[n.key]
                if links and n.key ~= best.key then
                    local w = WP(n.m, n.x, n.y)
                    if w and bw and w[3] == bw[3] then links[best.key] = true end
                end
            end
            State.lastWP = nil
            Flow.ScheduleAdvance()
        end
    end
end

-- Meilleur vol entre deux points du meme continent (ou nil s'il ne fait pas gagner assez de temps).
-- v1.45 : prev = vol deja conseille ; on le garde tant qu'il fait encore gagner du temps, meme sous les seuils,
-- pour que le conseil ne change pas d'avis en chemin (il est maintenant recalcule pendant la marche).
function BestFlight(a, b, known, prev)
    if not (a and b) or a[3] ~= b[3] then return nil end
    local walk = Walk(a, b)
    local best, bestCost, prevPlan, prevCost
    -- v1.47 : marche de chaque point de vol vers l'objectif calculee une seule fois (avant : pour chaque paire,
    -- 18 x 18 = 324 fois chez un joueur a 18 points ; 178 646 Walk en une minute, saccades de 170 ms)
    local fromB = {}
    for k, B in ipairs(known) do if B.w[3] == a[3] then fromB[k] = Walk(B.w, b) end end
    for _, A in ipairs(known) do
        if A.w[3] == a[3] then
            local toA = Walk(a, A.w)
            for k, B in ipairs(known) do
                if B ~= A and fromB[k] and CanFly(A.node.key, B.node.key) then
                    local c = toA + Dist(A.w[1], A.w[2], B.w[1], B.w[2]) * FLY_FACTOR + FLY_OVERHEAD
                        + fromB[k]
                    if not bestCost or c < bestCost then best, bestCost = { from = A.node, to = B.node }, c end
                    if prev and prev.from and prev.to and A.node.key == prev.from.key and B.node.key == prev.to.key then
                        prevPlan, prevCost = { from = A.node, to = B.node }, c
                    end
                end
            end
        end
    end
    if best and bestCost < walk * 0.85 and walk - bestCost > 200 then
        -- le vol deja conseille reste s'il est presque aussi bon (a 5 % pres)
        if prevPlan and prevCost <= bestCost * 1.05 then return prevPlan, prevCost end
        return best, bestCost
    end
    if prevPlan and prevCost < walk then return prevPlan, prevCost end
    return nil, walk
end

function TravelCost(a, b, known)
    if not (a and b) then return nil end
    if a[3] == b[3] then
        local _, c = BestFlight(a, b, known or {})
        local walk = Walk(a, b)
        return math.min(c or walk, walk)
    end
    local best
    for _, tr in ipairs(TRANSPORTS) do
        local f1 = WP(tr.from[1], tr.from[2], tr.from[3])
        local t1 = WP(tr.to[1], tr.to[2], tr.to[3])
        if f1 and t1 and f1[3] == a[3] and t1[3] == b[3] then
            local c = Walk(a, f1) + RIDE + Walk(t1, b)
            if not best or c < best then best = c end
        end
    end
    return best
end

-- Ordre le plus court pour ramasser les quetes d'un donjon (programmation dynamique sur les sous-ensembles,
-- en respectant les chaines : on ne prend jamais une quete avant d'avoir rendu son prerequis).
optCache = { key = nil, seq = nil }
band = bit and bit.band

OptimizeFn = function()
    local n = #State.steps
    local entrance
    for i = 1, n do if State.steps[i].t == "go" then entrance = i; break end end
    if not entrance then return nil end
    -- une prise bloquee par un prerequis encore dans ton journal (ex. Hamuul Runetotem tant qu'Altered Beings
    -- n'est pas rendue) reste dans le calcul : on y passe par le detour (finir / rendre le prerequis), puis on la prend.
    -- Seulement si le detour n'a pas de position : elle passe a la fin, avec tout ce qui en depend.
    local later, via, detKey = {}, {}, {}
    for i = 1, entrance - 1 do
        local s = State.steps[i]
        local det = PrereqDetour and PrereqDetour(s)
        if det then
            local w = det.m and WP(det.m, det.x, det.y)
            if w then via[i] = w; detKey[#detKey + 1] = i .. (det.done and "d" or "o") else later[i] = true end
        end
        for _, d in ipairs(Core.depsOf[i] or {}) do if later[d] then later[i] = true end end
    end
    -- une etape sans position (quete prise dans le donjon, ou qui commence sur un objet) ne bloque plus le
    -- calcul : elle passe apres le ramassage, juste avant d'entrer.
    local P, tail = {}, {}
    for i = 1, entrance - 1 do
        local st = State.steps[i]
        if Core.Applies(st) and not State.doneCache[i] and st.t ~= "note" and not later[i] then
            if st.m and st.x and WP(st.m, st.x, st.y) then P[#P + 1] = i else tail[#tail + 1] = i end
        end
    end
    for i = 1, entrance - 1 do
        if later[i] and Core.Applies(State.steps[i]) and not State.doneCache[i] and State.steps[i].t ~= "note" then tail[#tail + 1] = i end
    end
    if #P == 0 then return tail[1] and tail or nil end
    local greedy = #P > 12      -- trop d'etapes pour le calcul exact : plus proche voisin (respecte les chaines)
    local start = PlayerWP()
    if not start then return nil end
    -- cache : on ne recalcule que quand une etape est faite (ou sur "Recalculer"), PAS a chaque deplacement :
    -- sinon l'ordre change en marchant et la prochaine etape saute d'un PNJ a l'autre.
    local key = DB.guide .. "|" .. table.concat(P, ",") .. "|" .. (next(later) and "L" or "") .. table.concat(detKey, ",") .. "|" .. (DB.useFlights ~= false and "f" or "") .. tostring(DB.fp and next(DB.fp))
    if optCache.key == key then return optCache.seq end
    local pos, slot = {}, {}
    for k, i in ipairs(P) do
        local st = State.steps[i]
        if not (st.m and st.x) then return nil end
        pos[k] = WP(st.m, st.x, st.y)
        if not pos[k] then return nil end
        slot[i] = k
    end
    local endPos = State.steps[entrance].m and WP(State.steps[entrance].m, State.steps[entrance].x, State.steps[entrance].y)
    -- masques de dependances (limites aux etapes en attente)
    local need = {}
    for k, i in ipairs(P) do
        local m = 0
        for _, d in ipairs(Core.depsOf[i] or {}) do
            if slot[d] then m = m + 2 ^ (slot[d] - 1) end
        end
        need[k] = m
    end
    local function has(mask, k) return math.floor(mask / 2 ^ (k - 1)) % 2 == 1 end
    local function hasAll(mask, req)
        if req == 0 then return true end
        if band then return band(mask, req) == req end
        local b = 1
        while req > 0 do
            if req % 2 == 1 and not has(mask, b) then return false end
            req = math.floor(req / 2); b = b + 1
        end
        return true
    end
    local K = #P
    local full = 2 ^ K - 1
    local known = (DB.useFlights ~= false) and KnownFlights() or {}
    local CM = {}                                   -- couts precalcules (avec vols connus)
    local function C(i, j)
        CM[i] = CM[i] or {}
        local v = CM[i][j]
        if v == nil then
            local a = (i == 0) and start or pos[i]
            local b = (j == -1) and endPos or pos[j]
            local w = (j ~= -1) and via[P[j]]
            if w then
                local c1, c2 = TravelCost(a, w, known), TravelCost(w, b, known)
                v = (c1 and c2) and (c1 + c2) or false
            else
                v = TravelCost(a, b, known) or false
            end
            CM[i][j] = v
        end
        return v or nil
    end
    if greedy then
        local seq, done, last, mask = {}, {}, 0, 0
        for _ = 1, K do
            local bk, bc
            for k = 1, K do
                if not done[k] and hasAll(mask, need[k]) then
                    local c = C(last, k) or 1e9
                    if not bc or c < bc then bk, bc = k, c end
                end
            end
            if not bk then break end
            done[bk] = true; mask = mask + 2 ^ (bk - 1); last = bk
            seq[#seq + 1] = P[bk]
        end
        for k = 1, K do if not done[k] then seq[#seq + 1] = P[k] end end
        for _, i in ipairs(tail) do seq[#seq + 1] = i end
        optCache.key, optCache.seq = key, seq
        return seq
    end
    local dp, from = {}, {}
    for k = 1, K do
        if need[k] == 0 then
            local c = C(0, k)
            if c then
                local m = 2 ^ (k - 1)
                dp[m] = dp[m] or {}; from[m] = from[m] or {}
                dp[m][k] = c
            end
        end
    end
    for mask = 1, full do
        local row = dp[mask]
        if row then
            for last, cost in pairs(row) do
                for k = 1, K do
                    if not has(mask, k) and hasAll(mask, need[k]) then
                        local c = C(last, k)
                        if c then
                            local nm = mask + 2 ^ (k - 1)
                            dp[nm] = dp[nm] or {}; from[nm] = from[nm] or {}
                            local v = cost + c
                            if not dp[nm][k] or v < dp[nm][k] then dp[nm][k] = v; from[nm][k] = last end
                        end
                    end
                end
            end
        end
    end
    local bestLast, bestCost
    for k, cost in pairs(dp[full] or {}) do
        local total = cost + ((endPos and C(k, -1)) or 0)
        if not bestCost or total < bestCost then bestLast, bestCost = k, total end
    end
    if not bestLast then return nil end
    local seq, mask, k = {}, full, bestLast
    while k do
        table.insert(seq, 1, P[k])
        local prev = from[mask] and from[mask][k]
        mask = mask - 2 ^ (k - 1)
        k = prev
    end
    for _, i in ipairs(tail) do seq[#seq + 1] = i end
    optCache.key, optCache.seq = key, seq
    return seq
end

-- Etape "Prendre" bloquee par un prerequis qui est DANS ton journal mais pas encore rendu :
-- renvoie ou aller pour finir ce prerequis (objectif, ou PNJ a qui le rendre s'il est complete).
function PrereqDetour(s)
    if not s or s.t ~= "accept" then return nil end
    local blockers = {}
    for _, p in ipairs(s.preg or {}) do if not Rendue(p) then blockers[#blockers + 1] = p end end
    if s.pre then
        local ok = false
        for _, p in ipairs(s.pre) do if Rendue(p) then ok = true end end
        if not ok then for _, p in ipairs(s.pre) do blockers[#blockers + 1] = p end end
    end
    for _, p in ipairs(blockers) do
        if Core.logById[p] ~= nil then
            local done = Core.logById[p] == true
            local want = done and "turnin" or "do"
            local m, x, y
            for _, t in ipairs(State.steps) do
                if t.t == want and t.m and t.x then
                    for _, id in ipairs(Core.Ids(t)) do if id == p then m, x, y = t.m, t.x, t.y; break end end
                end
                if m then break end
            end
            local e = Est.EST[p]
            if not m and e then
                local c = done and e.e or (e.h or e.e or e.s)
                if c then m, x, y = c[1], c[2], c[3] end
            end
            if m then return { id = p, done = done, m = m, x = x, y = y, name = Core.QuestTitle(p) or (e and e.n) or ("#" .. p) } end
        end
    end
end

-- v1.50 : ce que ce fichier offre aux autres (ns.Mod.Route)
do
    local M = ns.Mod.Route
    M.Continent = Continent
    M.Dist = Dist
    M.FLIGHTS = FLIGHTS
    M.GATES = GATES
    M.LearnFlightHere = LearnFlightHere
    M.PCOL = PCOL
    M.PREFIX = PREFIX
    M.PrereqDetour = PrereqDetour
    M.TRANSPORTS = TRANSPORTS
    M.WorldPos = WorldPos
    M.ZoneOf = ZoneOf
    M.band = band
    M.optCache = optCache
end
