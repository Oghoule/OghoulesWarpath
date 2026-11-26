-- Oghoule's Warpath : quetes speciales (v1.52). Chaines a part (ex. Cozy Sleeping Bag, +3 % sur toute l'XP) lancees
-- comme un detour : le guide « chain » prend les etapes du guide sp_<nom> (Data/Guides.lua, routes_special.py dans
-- les outils), reprend la ou tu en es, puis te ramene a ta zone (Flow.Advance). Proposition au bon moment (parcours
-- Eclaireur, dans une capitale a zeppelins), ligne dans Options > Classe, « Faire maintenant ».
local ADDON, ns = ...
local State = ns.State
local Special = ns.Mod.Special
local Core = ns.Mod.Core
local Flow = ns.Mod.Flow
local Skin = ns.Mod.Skin
local Route = ns.Mod.Route

-- noms propres a ce fichier
local LIST = {
    { key = "bag", guide = "sp_bag", final = 79976, minLvl = 14, maxLvl = 52, name = "spBagName", why = "spBagWhy",
      quests = { 79007, 79192, 79980, 79974, 79975, 79976 } },
}
local CAPITALS = { [1454] = true, [1458] = true }   -- Orgrimmar, Undercity : les zeppelins partent de la
local REASK = 3                                      -- niveaux avant de reproposer apres « Plus tard »
local asking = nil

local function byKey(k) for _, s in ipairs(LIST) do if s.key == k then return s end end end

-- "done" (finie), "doing" (commencee : n quetes rendues sur le total) ou "todo"
function Special.State(k)
    local s = byKey(k); if not s then return nil, 0, 0 end
    if Core.Rendue(s.final) then return "done", #s.quests, #s.quests end
    local n, started = 0, false
    for _, q in ipairs(s.quests) do
        if Core.Rendue(q) then n = n + 1; started = true elseif Core.logById[q] ~= nil then started = true end
    end
    return started and "doing" or "todo", n, #s.quests
end

function Special.List()
    local out = {}
    for _, s in ipairs(LIST) do
        if Core.Guides[s.guide] then
            local st, n, tot = Special.State(s.key)
            out[#out + 1] = { key = s.key, name = Core.T(s.name), state = st, n = n, total = tot, lvl = s.minLvl }
        end
    end
    return out
end

-- guide du detour (aussi recree a la connexion, Events.lua) : les etapes du guide sp_<nom>, sous la cle « chain »
function Special.Guide(k)
    local s = byKey(k); local g = s and Core.Guides[s.guide]
    if not g then return nil end
    return { title = g.title, title_en = g.title_en, races = g.races, steps = g.steps, side = true }
end

function Special.Start(k)
    local g = Special.Guide(k)
    if not g then return end
    if State.DB.guide ~= "chain" then State.DB.chainBack = State.DB.guide end
    State.DB.chainQ, State.DB.chainSelf, State.DB.chainSpecial = nil, nil, k
    Core.Guides.chain = g
    Core.say(Core.T("spStart", Core.T(byKey(k).name)))
    Flow.SetGuide("chain", true)
end

local function later(k)
    State.DB.spAsk = State.DB.spAsk or {}
    State.DB.spAsk[k] = UnitLevel and UnitLevel("player") or 1
end

-- fenetre : depuis les options (fromOptions) sans « Jamais »
function Special.Ask(k, fromOptions)
    local s = byKey(k)
    if not (s and Core.Guides[s.guide]) then return end
    local st, n, tot = Special.State(k)
    if st == "done" then Core.say(Core.T("spDoneMsg", Core.T(s.name))); return end
    asking = k
    StaticPopupDialogs["WARPATH_SPECIAL"] = StaticPopupDialogs["WARPATH_SPECIAL"] or {
        text = "%s", timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function() if asking then Special.Start(asking) end end,
        OnCancel = function(_, _, reason) if asking and reason == "clicked" then later(asking) end end,
        OnAlt = function() if asking then State.DB.spNo = State.DB.spNo or {}; State.DB.spNo[asking] = true end end,
    }
    local d = StaticPopupDialogs["WARPATH_SPECIAL"]
    d.button1, d.button2 = Core.T("spGo"), Core.T("spLater")
    d.button3 = (not fromOptions) and Core.T("spNever") or nil
    d.headKey = "popSpecial"
    local where = (st == "doing") and Core.T("spWhere", n, tot) or ""
    ns.Trace("popup WARPATH_SPECIAL"); Skin.Popup("WARPATH_SPECIAL", Core.T(s.why) .. where)
end

-- proposition au bon moment : parcours Eclaireur (la Bande de guerre a la chaine dans son trajet), niveau assez haut,
-- dans une capitale a zeppelins, hors combat et hors donjon, pas deja en detour. Redemande REASK niveaux plus tard.
function Special.Check()
    if not State.DB or not State.steps then return end
    if Core.Parcours() ~= "scout" then return end
    if State.asking or State.DB.guide == "chain" or Core.IS_DUNGEON[State.DB.guide] then return end
    if (InCombatLockdown and InCombatLockdown()) or (IsInInstance and IsInInstance()) then return end
    if StaticPopup_Visible and StaticPopup_Visible("WARPATH_SPECIAL") then return end
    local me = Route.PlayerWP and Route.PlayerWP()
    if not (me and me[4] and CAPITALS[me[4]]) then return end
    local lvl = UnitLevel and UnitLevel("player") or 1
    for _, s in ipairs(LIST) do
        if Core.Guides[s.guide] and not (State.DB.spNo and State.DB.spNo[s.key]) and lvl >= s.minLvl and lvl <= s.maxLvl
           and Special.State(s.key) ~= "done" then
            local asked = State.DB.spAsk and State.DB.spAsk[s.key]
            if not asked or lvl >= asked + REASK then
                later(s.key)
                Special.Ask(s.key, false)
                return
            end
        end
    end
end

if not WARPATH_TEST and C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(20, function() pcall(Special.Check) end)
end
