-- Oghoule's Warpath : points de passage (tunnels). ns.Passages[quete] = { carte, x, y } : entree du tunnel.
-- La fleche vise l'entree tant que tu es plus loin de l'objectif que l'entree ; une fois passe, l'objectif.
-- Positions relevees en jeu (/warpath diag).
local _, ns = ...
ns.Passages = {
    [835] = { 1411, 51.8, 27.4 },   -- Securing the Lines : tunnel vers Drygulch Ravine (cote Rezlak)
    ["rendre:835"] = { 1411, 51.8, 27.4 },   -- et le retour vers Rezlak depuis le ravin
}
