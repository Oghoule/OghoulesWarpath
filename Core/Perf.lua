-- Oghoule's Warpath : moteur (Perf.lua) - mesure des performances (/warpath perf), voir Core.lua
-- v1.47 (saccades toujours signalees par un joueur, disparues sans l'addon) : pendant N secondes, chaque fonction
-- du moteur listee ci-dessous est chronometree (temps inclusif, appels, maximum) et sa memoire allouee comptee (Ko,
-- inclusif). On repere aussi les images lentes (petites saccades comprises), leur intervalle moyen, les nettoyages
-- de memoire du jeu (baisse de collectgarbage("count")) et s'ils tombent sur les saccades, les poses/effacements du
-- repere du jeu, et la memoire allouee par seconde (Warpath / tous addons). Resultat dans le chat et dans
-- WarpathDropDB._perf. Rien n'est mesure en dehors d'une mesure demandee : les fonctions d'origine sont remises.
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end
local Core = ns.Mod.Core -- v1.50 : module
-- v1.50 : module ns.Mod.Perf (publie en fin de fichier pour les autres fichiers)
local PerfMark, PerfMem, PerfStart

PerfOn = false

local NAMES = { "UpdateDistance", "NearTick", "NearPick", "StepPoint", "TrailPoint", "CaveTrack", "Refresh",
    "RefreshInner", "RetargetLight", "UpdateMini", "HearthPlace", "Advice", "BestFlight", "TravelCost", "Walk",
    "TransportFor", "KnownFlights", "Estimate", "LockCandidates", "Compute", "ScanLog", "LearnGates", "TrailTick",
    "PlaceNative", "SetWaypoint", "ClearWaypoint", "CheckDungeonLeft", "PlayerWP", "WP", "OnTheWay" }
local TABLES = { { "Comfort", "UpdateInfo" }, { "Targets", "Update" }, { "Targets", "Refresh" } }

local stats, saved, depth = {}, {}, 0
local frameMs, frameTop, frameTopMs = 0, nil, 0
local frames, avg, hitches, hitchList, hitchT, hitchGC = 0, nil, 0, {}, {}, 0
local gcFrames, wpSet, wpClear, memSum, wpKB, memPrev = 0, 0, 0, 0, 0, nil
local hooked = false
local now = function() return debugprofilestop and debugprofilestop() or 0 end
local mem = function() return collectgarbage and collectgarbage("count") or 0 end

local function add(name, ms, kb, top)
    local st = stats[name]; if not st then st = { n = 0, t = 0, mx = 0, kb = 0 }; stats[name] = st end
    st.n, st.t, st.kb = st.n + 1, st.t + ms, st.kb + kb
    if ms > st.mx then st.mx = ms end
    if top then                                  -- seulement les appels du haut : pas de double compte
        frameMs, wpKB = frameMs + ms, wpKB + kb
        if ms > frameTopMs then frameTop, frameTopMs = name, ms end
    end
end

-- temps et memoire d'un bloc qui n'est pas une fonction partagee (ex. le ticker de la fleche, 25 fois par seconde)
function PerfMark(name, ms, kb)
    add(name, ms, (kb and kb > 0) and kb or 0, true)
end
function PerfMem() return mem() end

-- sans table intermediaire (elle fausserait la memoire mesuree) : les resultats passent par les arguments
local function finish(name, t0, m0, ok, ...)
    local ms, kb = now() - t0, mem() - m0
    depth = depth - 1
    add(name, ms, kb > 0 and kb or 0, depth == 0)   -- kb < 0 : le jeu a nettoye pendant l'appel
    if not ok then error((...), 0) end
    return ...
end
local function wrap(name, fn)
    return function(...)
        depth = depth + 1
        local m0, t0 = mem(), now()
        return finish(name, t0, m0, pcall(fn, ...))
    end
end

local function install()
    local env = ns.CoreEnv
    for _, n in ipairs(NAMES) do
        local fn = rawget(env, n)
        if type(fn) == "function" then saved[#saved + 1] = { env, n, fn }; env[n] = wrap(n, fn) end
    end
    for _, p in ipairs(TABLES) do
        local t = ns[p[1]]
        local fn = type(t) == "table" and t[p[2]]
        if type(fn) == "function" then saved[#saved + 1] = { t, p[2], fn }; t[p[2]] = wrap(p[1] .. "." .. p[2], fn) end
    end
end

local function uninstall()
    for _, s in ipairs(saved) do s[1][s[2]] = s[3] end
    saved = {}
end

local function report(secs)
    local list = {}
    for name, st in pairs(stats) do list[#list + 1] = { name = name, n = st.n, t = st.t, mx = st.mx, kb = st.kb } end
    local out = { T("perfHead", secs, Core.VERSION or "?") }
    table.sort(list, function(a, b) return a.t > b.t end)
    for i = 1, math.min(8, #list) do local e = list[i]; out[#out + 1] = T("perfLine", e.name, e.n, e.t, e.mx, e.kb) end
    -- memoire : les plus gros producteurs (souvent les memes, mais pas toujours)
    table.sort(list, function(a, b) return a.kb > b.kb end)
    out[#out + 1] = T("perfMemHead")
    for i = 1, math.min(6, #list) do local e = list[i]; out[#out + 1] = T("perfMemLine", e.name, e.kb / secs, e.n > 0 and e.kb * 1024 / e.n or 0) end
    -- saccades : nombre, intervalle moyen, part pendant un nettoyage de memoire du jeu
    local gap = 0
    if #hitchT > 1 then gap = (hitchT[#hitchT] - hitchT[1]) / (#hitchT - 1) end
    out[#out + 1] = T("perfHitch", frames, hitches, gap)
    for i = 1, math.min(5, #hitchList) do
        local h = hitchList[i]
        out[#out + 1] = T("perfHitchItem", h.ms, h.wp, h.top or "-", h.gc and T("perfGcYes") or "")
    end
    out[#out + 1] = T("perfGC", gcFrames, hitchGC, hitches)
    out[#out + 1] = T("perfWP", wpSet, wpClear)
    out[#out + 1] = T("perfMem", wpKB / secs, memSum / secs)
    for _, l in ipairs(out) do say(l, true) end
    say(T("perfSaved"), true)
    if WarpathDropDB then
        WarpathDropDB._perf = { when = date and date("%Y-%m-%d %H:%M") or "", lines = out }
    end
end

function PerfStart(secs)
    if PerfOn then say(T("perfBusy"), true); return end
    secs = math.max(10, math.min(300, secs or 60))
    stats, depth, frameMs, frameTop, frameTopMs = {}, 0, 0, nil, 0
    frames, avg, hitches, hitchList, hitchT, hitchGC = 0, nil, 0, {}, {}, 0
    gcFrames, wpSet, wpClear, memSum, wpKB, memPrev = 0, 0, 0, 0, 0, mem()
    -- poses et effacements du repere du jeu, par n'importe qui (hooksecurefunc ne gene pas le jeu)
    if not hooked and hooksecurefunc and C_Map then
        hooked = true
        pcall(hooksecurefunc, C_Map, "SetUserWaypoint", function() if PerfOn then wpSet = wpSet + 1 end end)
        pcall(hooksecurefunc, C_Map, "ClearUserWaypoint", function() if PerfOn then wpClear = wpClear + 1 end end)
    end
    install()
    PerfOn = true
    say(T("perfStart", secs), true)
    local fr = CreateFrame("Frame")
    local t = 0
    fr:SetScript("OnUpdate", function(self, el)
        el = el or 0
        t = t + el
        frames = frames + 1
        -- memoire : hausse = allocations ; baisse de plus de 16 Ko = le jeu a nettoye pendant cette image
        local m = mem()
        local gc = false
        if memPrev then
            if m > memPrev then memSum = memSum + (m - memPrev)
            elseif memPrev - m > 16 then gc = true; gcFrames = gcFrames + 1 end
        end
        memPrev = m
        -- petite saccade : plus de 25 ms et plus de 1,8 fois la moyenne recente
        local ms = el * 1000
        if avg and ms > 25 and ms > avg * 1.8 then
            hitches = hitches + 1
            hitchT[#hitchT + 1] = t
            if gc then hitchGC = hitchGC + 1 end
            hitchList[#hitchList + 1] = { ms = ms, wp = frameMs, gc = gc,
                top = frameTop and string.format("%s %.1f ms", frameTop, frameTopMs) }
            table.sort(hitchList, function(a, b) return a.ms > b.ms end)
            while #hitchList > 5 do table.remove(hitchList) end
        end
        avg = avg and (avg * 0.95 + ms * 0.05) or ms
        frameMs, frameTop, frameTopMs = 0, nil, 0
        if t >= secs then
            self:SetScript("OnUpdate", nil)
            PerfOn = false
            uninstall()
            pcall(report, secs)
        end
    end)
end

-- v1.50 : ce que ce fichier offre aux autres (ns.Mod.Perf)
do
    local M = ns.Mod.Perf
    M.PerfMark = PerfMark
    M.PerfMem = PerfMem
    M.PerfStart = PerfStart
end
