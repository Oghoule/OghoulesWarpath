-- Oghoule's Warpath : registre des modules (v1.50, refonte de l'architecture)
-- Chaque fichier du moteur publie ce qu'il offre aux autres dans ns.Mod.<Fichier> (ex. ns.Mod.Route.WP),
-- a la fin du fichier. Les autres le lisent par un alias en tete : local Route = ns.Mod.Route
-- Les tables sont creees a la demande : un fichier peut prendre l'alias avant que le module soit charge
-- (les appels, eux, se font en jeu, une fois tout charge).
-- ns.ModIndex[nom] = module qui publie ce nom : sert a ns.CoreEnv (Core.lua) pour retrouver les anciens noms
-- (outils de test, /run), sans chercher dans tous les modules.
local ADDON, ns = ...

local index = {}
ns.ModIndex = index

local function newModule()
    return setmetatable({}, { __newindex = function(t, k, v) index[k] = t; rawset(t, k, v) end })
end

ns.Mod = setmetatable({}, { __index = function(t, name)
    local m = newModule()
    rawset(t, name, m)
    return m
end })
