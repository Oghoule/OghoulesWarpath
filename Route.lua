-- Oghoule's Warpath : moteur (Route.lua) - voir Core.lua
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end

------------------------------------------------------------------
-- Waypoints (natif si possible, TomTom si installe)
------------------------------------------------------------------
desiredWP = nil -- waypoint voulu par le guide (on le remet si le jeu l'efface a l'arrivee)

function ClearWaypoint()
    desiredWP = nil
    if C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
    if tomtomWP and TomTom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, tomtomWP) end
    tomtomWP = nil
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
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
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
            tomtomWP = TomTom:AddWaypoint(mapID, s.x / 100, s.y / 100,
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
    return (PREFIX[s.t] or "") .. " " .. (QName(s) or StepText(s):sub(1, 45))
end

------------------------------------------------------------------
-- Changement de continent : zeppelins / bateau les plus rapides
------------------------------------------------------------------
KALIMDOR, EK, CONT_FALLBACK, TRANSPORTS = D.KALIMDOR, D.EK, D.CONT_FALLBACK, D.TRANSPORTS

function Continent(mapID)
    if not mapID then return nil end
    if C_Map and C_Map.GetMapInfo then
        local m, guard = mapID, 0
        while m and m > 0 and guard < 10 do
            local info = C_Map.GetMapInfo(m)
            if not info then break end
            if info.mapType == 2 then return m end      -- Enum.UIMapType.Continent
            m, guard = info.parentMapID, guard + 1
        end
    end
    return CONT_FALLBACK[mapID]
end

function WorldPos(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, _, v = pcall(ns.MapAPI.WorldFromMap, mapID, x / 100, y / 100)
    if ok and v then return v.x, v.y end
end

function PlayerPos()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local m = C_Map.GetBestMapForUnit("player")
    if not m then return nil end
    local okp, p = pcall(ns.MapAPI.PlayerPos, m, "player")
    if not okp then p = nil end
    if p then
        local x, y = p:GetXY()
        if x and (x > 0 or y > 0) then return m, x * 100, y * 100 end
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

function PlayerWP()
    local pm, px, py = PlayerPos()
    if not (pm and px) then return nil end
    local wx, wy = WorldPos(pm, px, py)
    return wx and { wx, wy, Continent(pm), pm } or nil
end

------------------------------------------------------------------
-- Trajet a pied realiste : les zones ne communiquent que par leurs passages (graphe + Dijkstra).
-- Les passages connus sont dans Data.lua ; ceux que tu traverses sont appris (DB.gates).
------------------------------------------------------------------
GATES = D.GATES or {}
WIND, UNKNOWN = 1.15, 1.35          -- detours d'un chemin reel / zone sans passage connu
function ZoneOf(m)
    if not m then return nil end
    if C_Map and C_Map.GetMapInfo then
        local cur, guard = m, 0
        while cur and cur > 0 and guard < 6 do
            local info = C_Map.GetMapInfo(cur)
            if not info then break end
            if (info.mapType or 3) <= 3 then return cur end
            cur, guard = info.parentMapID, guard + 1
        end
    end
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
    local nodes = {}
    for _, g in ipairs(GateNodes()) do if g[3] == a[3] then nodes[#nodes + 1] = g end end
    local ck = za .. ">" .. zb .. ":" .. math.floor(a[1] / 50) .. ":" .. math.floor(a[2] / 50) .. ":"
        .. math.floor(b[1] / 50) .. ":" .. math.floor(b[2] / 50)
    if walkCache[ck] then return walkCache[ck] end
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
function CanFly(aKey, bKey)
    local links = DB and DB.fpLinks and DB.fpLinks[aKey]
    if not links then return true end
    return links[bKey] and true or false
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

-- Meilleur vol entre deux points du meme continent (ou nil s'il ne fait pas gagner assez de temps).
function BestFlight(a, b, known)
    if not (a and b) or a[3] ~= b[3] then return nil end
    local walk = Walk(a, b)
    local best, bestCost
    for _, A in ipairs(known) do
        if A.w[3] == a[3] then
            local toA = Walk(a, A.w)
            for _, B in ipairs(known) do
                if B ~= A and B.w[3] == a[3] and CanFly(A.node.key, B.node.key) then
                    local c = toA + Dist(A.w[1], A.w[2], B.w[1], B.w[2]) * FLY_FACTOR + FLY_OVERHEAD
                        + Walk(B.w, b)
                    if not bestCost or c < bestCost then best, bestCost = { from = A.node, to = B.node }, c end
                end
            end
        end
    end
    if best and bestCost < walk * 0.85 and walk - bestCost > 200 then return best, bestCost end
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
    local n = #steps
    local entrance
    for i = 1, n do if steps[i].t == "go" then entrance = i; break end end
    if not entrance then return nil end
    -- une prise bloquee par un prerequis encore en cours (ex. Hamuul Runetotem tant qu'Altered Beings
    -- n'est pas rendue) passe a la fin, avec tout ce qui en depend : on ramasse d'abord ce qui est possible.
    local later = {}
    for i = 1, entrance - 1 do
        local s = steps[i]
        if PrereqDetour and PrereqDetour(s) then later[i] = true end
        for _, d in ipairs(depsOf[i] or {}) do if later[d] then later[i] = true end end
    end
    local P = {}
    for i = 1, entrance - 1 do
        if Applies(steps[i]) and not doneCache[i] and steps[i].t ~= "note" and not later[i] then P[#P + 1] = i end
    end
    local tail = {}
    for i = 1, entrance - 1 do
        if later[i] and Applies(steps[i]) and not doneCache[i] and steps[i].t ~= "note" then tail[#tail + 1] = i end
    end
    if #P == 0 then return tail[1] and tail or nil end
    if #P > 10 then return nil end
    local start = PlayerWP()
    if not start then return nil end
    -- cache : on ne recalcule que quand une etape est faite (ou sur "Recalculer"), PAS a chaque deplacement :
    -- sinon l'ordre change en marchant et la prochaine etape saute d'un PNJ a l'autre.
    local key = DB.guide .. "|" .. table.concat(P, ",") .. "|" .. (next(later) and "L" or "") .. "|" .. (DB.useFlights ~= false and "f" or "") .. tostring(DB.fp and next(DB.fp))
    if optCache.key == key then return optCache.seq end
    local pos, slot = {}, {}
    for k, i in ipairs(P) do
        local st = steps[i]
        if not (st.m and st.x) then return nil end
        pos[k] = WP(st.m, st.x, st.y)
        if not pos[k] then return nil end
        slot[i] = k
    end
    local endPos = steps[entrance].m and WP(steps[entrance].m, steps[entrance].x, steps[entrance].y)
    -- masques de dependances (limites aux etapes en attente)
    local need = {}
    for k, i in ipairs(P) do
        local m = 0
        for _, d in ipairs(depsOf[i] or {}) do
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
            v = TravelCost(a, b, known) or false
            CM[i][j] = v
        end
        return v or nil
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
        if logById[p] ~= nil then
            local done = logById[p] == true
            local want = done and "turnin" or "do"
            local m, x, y
            for _, t in ipairs(steps) do
                if t.t == want and t.m and t.x then
                    for _, id in ipairs(Ids(t)) do if id == p then m, x, y = t.m, t.x, t.y; break end end
                end
                if m then break end
            end
            local e = EST[p]
            if not m and e then
                local c = done and e.e or (e.h or e.e or e.s)
                if c then m, x, y = c[1], c[2], c[3] end
            end
            if m then return { id = p, done = done, m = m, x = x, y = y, name = QuestTitle(p) or (e and e.n) or ("#" .. p) } end
        end
    end
end
