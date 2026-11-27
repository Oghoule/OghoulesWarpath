-- Oghoule's Warpath : moteur (Style.lua) - style de jeu : quetes mises de cote selon tes reglages
-- (elites, escortes, prudence). Une quete qui en debloque une autre n'est jamais sautee.
-- v1.50 : sorti de Features/Comfort.lua (c'est le moteur qui decide quoi sauter ; Comfort garde les automatisations).
local ADDON, ns = ...
-- v1.50 : etat partage du guide (Core.lua, ns.State)
local State = ns.State
local Core = ns.Mod.Core -- v1.50 : module
local Est = ns.Mod.Est -- v1.50 : module
local Flow = ns.Mod.Flow -- v1.50 : module
-- v1.50 : module ns.Mod.Style (publie en fin de fichier pour les autres fichiers)
local ApplyPreset, QuestUnlocks, StyleGet, StyleSkip, StyleReset
-- noms propres a ce fichier
local ALL_NEEDED
local styleCache   -- donnees par guide (quetes qui debloquent la suite, lieux), refaites au changement de guide

------------------------------------------------------------------
-- Style de jeu (s'applique a tous les guides 1-60, pas aux donjons ni aux mini-guides de chaine) :
--   elite = "always" | "group" | "never" ; xpMode = "farm" | "dungeon" | "both" ;
--   noEscort, prudent = true/false
-- (v1.52 : la « priorite » XP/h ou trajets est retiree : mesuree sur tout le 1-60, XP/h sautait 1 seule quete et
-- « moins de trajets » sautait surtout des quetes de voyage utiles et des quetes de donjon de la Bande de guerre)
-- Une quete sautee par le style ne l'est jamais si elle debloque une autre quete du guide.
------------------------------------------------------------------
function StyleGet()
    State.DB.style = State.DB.style or {}
    local st = State.DB.style
    st.elite = st.elite or "always"; st.xpMode = st.xpMode or "farm"; st.prio = nil
    return st
end

local PRESETS = {
    solo = { elite = "never", xpMode = "both", noEscort = true, prudent = false },
    group = { elite = "always", xpMode = "dungeon", noEscort = false, prudent = false },
    calm = { elite = "group", xpMode = "farm", noEscort = false, prudent = false },
    safe = { elite = "never", xpMode = "farm", noEscort = true, prudent = true },
}
function ApplyPreset(name)
    local p = PRESETS[name]; if not p then return end
    local st = StyleGet()
    for k, v in pairs(p) do st[k] = v end
    styleCache = nil
    if Flow.Advance then Flow.Advance() end
end

-- donnees par guide : quetes qui debloquent la suite
local function GuideData()
    if styleCache and styleCache.G == State.G then return styleCache end
    local needed = {}
    for i, s in ipairs(State.steps or {}) do
        local ids = Core.Ids(s)
        for _, id in ipairs(ids) do
            local e = Est.EST[id]
            if e then
                for _, p in ipairs(e.p or {}) do needed[p] = true end
                for _, p in ipairs(e.p1 or {}) do needed[p] = true end
            end
        end
    end
    -- une quete qui debloque une quete d'un AUTRE guide (ex. Barrens -> Stonetalon) est aussi protegee
    if not ALL_NEEDED then
        ALL_NEEDED = {}
        for _, g in pairs(Core.Guides or {}) do
            for _, st in ipairs(g.steps or {}) do
                for _, id in ipairs(Core.Ids(st)) do
                    local e = Est.EST[id]
                    if e then
                        for _, p in ipairs(e.p or {}) do ALL_NEEDED[p] = true end
                        for _, p in ipairs(e.p1 or {}) do ALL_NEEDED[p] = true end
                    end
                end
            end
        end
    end
    for p in pairs(ALL_NEEDED) do needed[p] = true end
    styleCache = { G = State.G, needed = needed }
    return styleCache
end

-- v1.49 : la quete en debloque une autre (dans ce guide ou un guide suivant) : jamais mise de cote
function QuestUnlocks(id)
    if not (State.DB and State.steps and id) then return false end
    local ok, gd = pcall(GuideData)
    return ok and gd and gd.needed[id] and true or false
end

local function InGroup() return (IsInGroup and IsInGroup()) or ((GetNumGroupMembers and GetNumGroupMembers() or 0) > 0) end

function StyleSkip(i, s)
    if not State.DB or not State.steps or Core.IS_DUNGEON[State.DB.guide] or State.DB.guide == "chain" or s.t ~= "accept" then return false end
    local st = StyleGet()
    local gd = GuideData()
    local ids = Core.Ids(s)
    if #ids == 0 then return false end
    for _, id in ipairs(ids) do
        local e = Est.EST[id]
        if not e or gd.needed[id] then return false end
        local drop = (e.el and (st.elite == "never" or (st.elite == "group" and not InGroup())))
            or (e.es and st.noEscort)
            or (st.prudent and (e.l or 0) > (UnitLevel("player") or 1) + 2)
        if not drop then return false end
    end
    return true
end

-- reglages du style changes (Options) : les donnees par guide seront refaites
function StyleReset() styleCache = nil end

-- v1.50 : ce que ce fichier offre aux autres (ns.Mod.Style)
do
    local M = ns.Mod.Style
    M.ApplyPreset = ApplyPreset
    M.QuestUnlocks = QuestUnlocks
    M.StyleGet = StyleGet
    M.StyleSkip = StyleSkip
    M.StyleReset = StyleReset
end
