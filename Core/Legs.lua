-- Oghoule's Warpath : moteur (Legs.lua) - trajets a pied pre-calcules, voir Core.lua
-- Les chemins sont calcules HORS DU JEU (tools/gps/bake.lua) avec le routeur et les cartes de marche de
-- Shortest Path Forever par Cillian Berragan (GPL-3.0-or-later, github.com/cjber/shortest-path-forever),
-- puis reduits aux quelques points qui comptent (entree de grotte, col, pont, rampe). Rien n'est calcule en jeu.
-- Data/Legs.lua : ns.Legs["carte:x:y" de l'etape] = { { depart, point, point, ... }, ... } (chaque point = {carte, x, y}).
-- La fleche vise le prochain point du trajet le plus proche de toi ; loin de tout trajet (mort, detour), elle
-- revient a l'objectif et aux autres regles (passages, grottes, portes de ville), qui restent prioritaires.
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end
local Route = ns.Mod.Route -- v1.50 : module
-- v1.50 : module ns.Mod.Legs (publie en fin de fichier pour les autres fichiers)
local LegPoint

local ON_LEG = 120   -- yards : au-dela, tu n'es sur aucun trajet prevu
local NEAR_GOAL = 40 -- yards : assez pres de l'objectif, on le vise directement
local PASSED = 20    -- yards : un point de passage atteint compte comme passe

-- trajets d'une etape, en positions du monde (calcules une fois, gardes)
local worldCache = {}
local function legsFor(s)
    if not (ns.Legs and s and s.m and s.x) then return nil end
    local key = s.m .. ":" .. s.x .. ":" .. s.y
    local w = worldCache[key]
    if w == nil then
        w = false
        local raw = ns.Legs[key]
        local g = raw and WP(s.m, s.x, s.y)
        if g then
            w = {}
            for _, leg in ipairs(raw) do
                local pts, ok = {}, true
                for i, p in ipairs(leg) do
                    local v = WP(p[1], p[2], p[3])
                    if not v or v[3] ~= g[3] then ok = false; break end
                    pts[i] = { v[1], v[2], p[1], p[2], p[3] }
                end
                if ok then
                    pts[#pts + 1] = { g[1], g[2], s.m, s.x, s.y }
                    w[#w + 1] = { pts = pts, c = g[3] }
                end
            end
        end
        worldCache[key] = w
    end
    return w or nil
end

-- distance de (x, y) au segment a-b, et la position sur le segment (0 a 1)
local function segDist(x, y, a, b)
    local vx, vy = b[1] - a[1], b[2] - a[2]
    local L = vx * vx + vy * vy
    local t = L > 0 and math.max(0, math.min(1, ((x - a[1]) * vx + (y - a[2]) * vy) / L)) or 0
    return Route.Dist(x, y, a[1] + t * vx, a[2] + t * vy), t
end

-- le point a viser pour l'etape s, ou nil (pas de trajet, ou tu en es trop loin)
function LegPoint(s, me)
    if not (DB and DB.legs ~= false and me) then return nil end
    local legs = legsFor(s)
    if not legs then return nil end
    local best
    for _, leg in ipairs(legs) do
        local pts = leg.pts
        if leg.c == me[3] then
            local goal = pts[#pts]
            if Route.Dist(me[1], me[2], goal[1], goal[2]) <= NEAR_GOAL then return nil end
            for i = 1, #pts - 1 do
                local d, t = segDist(me[1], me[2], pts[i], pts[i + 1])
                if d <= ON_LEG and (not best or d < best.d) then best = { d = d, pts = pts, i = i, t = t } end
            end
        end
    end
    if not best then return nil end
    local pts, k = best.pts, best.i + 1
    -- point deja atteint : le suivant
    while k < #pts and Route.Dist(me[1], me[2], pts[k][1], pts[k][2]) <= PASSED do k = k + 1 end
    if k >= #pts then return nil end -- plus rien entre toi et l'objectif : la fleche normale suffit
    local p = pts[k]
    return { m = p[3], x = p[4], y = p[5], name = T("legVia"), kind = "leg" }
end

-- v1.50 : ce que ce fichier offre aux autres (ns.Mod.Legs)
do
    local M = ns.Mod.Legs
    M.LegPoint = LegPoint
end
