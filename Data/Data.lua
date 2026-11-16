-- Oghoule's Warpath : donnees fixes (ordre des zones, donjons, transports, points de vol)
local ADDON, ns = ...
local D = {}
ns.Data = D

D.CHAIN = {
    Tauren = { "mulgore", "barrens", "stonetalon", "ashenvale", "sbarrens", "hillsbrad", "needles", "desolace", "dustwallow", "stv1", "arathi", "riverglades", "stv2", "dustwallow2", "feralas", "tanaris", "hinterlands", "searing", "azshara", "tanaris2", "ungoro", "felwood", "steppes", "wpl", "epl", "winterspring", "hyjal", "silithus" },
    Orc = { "durotar", "barrens", "stonetalon", "ashenvale", "sbarrens", "hillsbrad", "needles", "desolace", "dustwallow", "stv1", "arathi", "riverglades", "stv2", "dustwallow2", "feralas", "tanaris", "hinterlands", "searing", "azshara", "tanaris2", "ungoro", "felwood", "steppes", "wpl", "epl", "winterspring", "hyjal", "silithus" },
    Troll = { "durotar", "barrens", "stonetalon", "ashenvale", "sbarrens", "hillsbrad", "needles", "desolace", "dustwallow", "stv1", "arathi", "riverglades", "stv2", "dustwallow2", "feralas", "tanaris", "hinterlands", "searing", "azshara", "tanaris2", "ungoro", "felwood", "steppes", "wpl", "epl", "winterspring", "hyjal", "silithus" },
    Scourge = { "tirisfal", "silverpine", "barrens", "stonetalon", "ashenvale", "sbarrens", "hillsbrad", "needles", "desolace", "dustwallow", "stv1", "arathi", "riverglades", "stv2", "dustwallow2", "feralas", "tanaris", "hinterlands", "searing", "azshara", "tanaris2", "ungoro", "felwood", "steppes", "wpl", "epl", "winterspring", "hyjal", "silithus" },
}
D.CHAIN.Undead = D.CHAIN.Scourge
-- Skyborne cote Horde (nouvelle race de Forever) : Zephras Isle, puis le meme parcours que les autres
D.CHAIN.Skyborne = { "zephras", "barrens", "stonetalon", "ashenvale", "sbarrens", "hillsbrad", "needles", "desolace", "dustwallow", "stv1", "arathi", "riverglades", "stv2", "dustwallow2", "feralas", "tanaris", "hinterlands", "searing", "azshara", "tanaris2", "ungoro", "felwood", "steppes", "wpl", "epl", "winterspring", "hyjal", "silithus" }
D.MAXLVL = { hyjal = 60, zephras = 12, mulgore = 11, durotar = 12, tirisfal = 11, silverpine = 16, barrens = 21,
             stonetalon = 25, ashenvale = 27, sbarrens = 28, hillsbrad = 30, needles = 33, desolace = 36,
             dustwallow = 39, stv1 = 41, arathi = 42, shendralas = 37, riverglades = 44, badlands = 45, swamp = 45, stv2 = 46, dustwallow2 = 47, tanaris = 47, feralas = 48, hinterlands = 50, stv3 = 49, searing = 48, tanaris2 = 50, azshara = 50, ungoro = 53, felwood = 51, steppes = 54, winterspring = 58, wpl = 56, epl = 58, winterspring2 = 60, silithus = 60 }

-- Donjons proposes (niveaux conseilles)
D.DUNGEONS = {
    { key = "rfc", name = "Ragefire Chasm", min = 13, max = 18 },
    { key = "rol", name = "Ruins of Lordaeron", min = 19, max = 25 },
    { key = "wc", name = "Wailing Caverns", min = 17, max = 24 },
    { key = "sfk", name = "Shadowfang Keep", min = 20, max = 27 },
    { key = "bfd", name = "Blackfathom Deeps", min = 23, max = 30 },
    { key = "rfk", name = "Razorfen Kraul", min = 25, max = 30 },
    { key = "excav", name = "Excavation Site", min = 26, max = 33 },
    { key = "gnomer", name = "Gnomeregan", min = 26, max = 34 },
    { key = "dalaran", name = "City of Dalaran", min = 30, max = 37 },
    { key = "sm_gy", name = "Scarlet Monastery : Graveyard", min = 28, max = 34 },
    { key = "sm_lib", name = "Scarlet Monastery : Library", min = 31, max = 37 },
    { key = "sm_arm", name = "Scarlet Monastery : Armory", min = 34, max = 40 },
    { key = "sm_cath", name = "Scarlet Monastery : Cathedral", min = 36, max = 42 },
    { key = "rfd", name = "Razorfen Downs", min = 35, max = 42 },
    { key = "uld", name = "Uldaman", min = 37, max = 45 },
    { key = "zf", name = "Zul'Farrak", min = 43, max = 50 },
    { key = "mara_out", name = "Maraudon : ailes orange et violette", min = 41, max = 48 },
    { key = "mara_in", name = "Maraudon : intérieur", min = 45, max = 52 },
    { key = "st", name = "Sunken Temple", min = 47, max = 55 },
    { key = "brd", name = "Blackrock Depths", min = 52, max = 60 },
    { key = "dm_e", name = "Dire Maul : est", min = 54, max = 58 },
    { key = "lbrs", name = "Lower Blackrock Spire", min = 55, max = 60 },
    { key = "dm_w", name = "Dire Maul : ouest", min = 56, max = 60 },
    { key = "ubrs", name = "Upper Blackrock Spire (groupe de 10)", min = 58, max = 60 },
    { key = "scholo", name = "Scholomance", min = 57, max = 60 },
    { key = "strat_live", name = "Stratholme : côté écarlate", min = 57, max = 60 },
    { key = "strat_ud", name = "Stratholme : côté mort-vivant", min = 58, max = 60 },
}
D.IS_DUNGEON = {}
for _, d in ipairs(D.DUNGEONS) do D.IS_DUNGEON[d.key] = d end

D.MINLVL = { hyjal = 55, zephras = 1, mulgore = 1, durotar = 1, tirisfal = 1, silverpine = 11, barrens = 12,
             stonetalon = 20, ashenvale = 23, sbarrens = 25, hillsbrad = 26, needles = 29, desolace = 32,
             dustwallow = 35, stv1 = 37, arathi = 38, shendralas = 35, riverglades = 39, badlands = 40, swamp = 41, stv2 = 40, dustwallow2 = 42, tanaris = 43, feralas = 42, hinterlands = 46, stv3 = 45, searing = 46, tanaris2 = 48, azshara = 47, ungoro = 48, felwood = 48, steppes = 50, winterspring = 55, wpl = 52, epl = 54, winterspring2 = 57, silithus = 57 }
D.MAIN_ORDER = { "zephras", "mulgore", "durotar", "tirisfal", "silverpine", "barrens",
                 "stonetalon", "ashenvale", "sbarrens", "hillsbrad", "needles", "desolace",
                 "dustwallow", "stv1", "arathi", "riverglades", "stv2", "dustwallow2", "feralas", "tanaris", "hinterlands", "searing", "azshara", "tanaris2", "ungoro", "felwood", "steppes", "wpl", "epl", "winterspring", "hyjal", "silithus" }

D.KALIMDOR, D.EK = 1414, 1415
-- Zones ajoutees par Forever : leur numero de carte est retrouve en jeu par leur nom (Core.lua, ResolveNewMaps).
D.NEWMAPS = {
    [-16591] = { "The Riverglades", "Riverglades" },
    [-16651] = { "Shen'dralas", "Shen'Dralas", "Valley of Bones" },
    [-16593] = { "Zephras Isle" },
    [-616] = { "Mount Hyjal", "Mont Hyjal", "Hyjal" },
}
D.CONT_FALLBACK = {}
for _, m in ipairs({ 1411, 1412, 1413, 1454, 1456, 1450, 1440, 1442, 1441, 1443, 1444, 1445, 1446, 1447, 1448,
                     1449, 1451, 1452, 1438, 1439, 1457 }) do D.CONT_FALLBACK[m] = D.KALIMDOR end
for _, m in ipairs({ 1416, 1417, 1418, 1419, 1420, 1421, 1422, 1423, 1424, 1425, 1426, 1427, 1428, 1429, 1430,
                     1431, 1432, 1433, 1434, 1435, 1436, 1437, 1453, 1455, 1458 }) do D.CONT_FALLBACK[m] = D.EK end

-- Positions des maitres de zeppelin et des shipmasters (Grimble, Grizzlowe) : base Questie de Forever.
D.TRANSPORTS = {
    { id = "zep_org_uc", kind = "zep", from = { 1411, 50.8, 13.5 }, to = { 1420, 60.7, 58.9 }, dest = "Undercity", where = "towerOrg" },
    { id = "zep_uc_org", kind = "zep", from = { 1420, 60.7, 58.9 }, to = { 1411, 50.8, 13.5 }, dest = "Orgrimmar", where = "towerUC" },
    { id = "zep_org_gg", kind = "zep", from = { 1411, 50.7, 12.9 }, to = { 1434, 31.4, 29.9 }, dest = "Grom'gol", where = "towerOrg" },
    { id = "zep_gg_org", kind = "zep", from = { 1434, 31.4, 29.9 }, to = { 1411, 50.7, 12.9 }, dest = "Orgrimmar", where = "towerGG" },
    { id = "boat_rat_bb", kind = "boat", from = { 1413, 63.5, 38.6 }, to = { 1434, 26.1, 73.3 }, dest = "Booty Bay", where = "dockRatchet" },
    { id = "boat_bb_rat", kind = "boat", from = { 1434, 26.1, 73.3 }, to = { 1413, 63.5, 38.6 }, dest = "Ratchet", where = "dockBB" },
    -- bateau de Forever Tanaris <-> Riverglades (positions des quais approximatives)
    { id = "boat_tan_rg", kind = "boat", from = { 1446, 67.5, 23.0 }, to = { -16591, 78.0, 52.5 }, dest = "Powderfuse Port", where = "dockSteamwheedle" },
    { id = "boat_rg_tan", kind = "boat", from = { -16591, 78.0, 52.5 }, to = { 1446, 67.5, 23.0 }, dest = "Steamwheedle Port", where = "dockPowderfuse" },
}

-- Points de vol Horde (positions des maitres de vol : base Questie de Forever).
-- key = morceau du nom affiche sur la carte de vol du jeu, pour reconnaitre les trajets appris.
-- Passages a pied entre zones (estimations ; l'addon apprend les vrais passages quand tu les traverses).
-- m,x,y : position sur une des deux cartes ; z : les deux zones reliees ; cost : surcout (ascenseur, etc.)
D.GATES = {
    { m = 1412, x = 36.8, y = 36.5, z = { 1456, 1412 }, cost = 40 },   -- ascenseurs de Thunder Bluff
    { m = 1413, x = 38.6, y = 58.8, z = { 1412, 1413 } },              -- route Mulgore -> Barrens (Camp Taurajo)
    { m = 1411, x = 34.4, y = 42.4, z = { 1413, 1411 } },              -- pont de la Southfury
    { m = 1411, x = 45.6, y = 11.5, z = { 1411, 1454 } },              -- porte d'Orgrimmar
    { m = 1413, x = 35.2, y = 27.8, z = { 1413, 1442 } },              -- Barrens -> Stonetalon (Windshear)
    { m = 1442, x = 77.5, y = 96.0, z = { 1413, 1442 } },              -- Barrens -> Malaka'Jin
    { m = 1413, x = 48.5, y = 4.8, z = { 1413, 1440 } },               -- Mor'shan -> Ashenvale
    { m = 1441, x = 31.9, y = 21.8, z = { 1413, 1441 }, cost = 60 },   -- Grande Ascension
    { m = 1442, x = 78.6, y = 42.6, z = { 1442, 1440 } },              -- Talondeep Path
    { m = 1443, x = 54.5, y = 5.0, z = { 1442, 1443 } },               -- Stonetalon -> Desolace
    { m = 1420, x = 61.9, y = 65.0, z = { 1420, 1458 }, cost = 40 },   -- entree d'Undercity
    { m = 1421, x = 67.5, y = 6.0, z = { 1420, 1421 } },               -- Tirisfal -> Silverpine
    { m = 1424, x = 14.0, y = 46.5, z = { 1421, 1424 } },              -- Silverpine -> Hillsbrad
}

D.FLIGHTS = {
    { key = "Sepulcher", name = "The Sepulcher", m = 1421, x = 45.6, y = 42.6 },
    { key = "Undercity", name = "Undercity", m = 1458, x = 63.2, y = 48.6 },
    { key = "Tarren Mill", name = "Tarren Mill", m = 1424, x = 60.1, y = 18.6 },
    { key = "Hammerfall", name = "Hammerfall", m = 1417, x = 73.0, y = 32.7 },
    { key = "Kargath", name = "Kargath", m = 1418, x = 4.0, y = 44.8 },
    { key = "Thorium Point", name = "Thorium Point", m = 1427, x = 34.8, y = 30.9 },
    { key = "Grom'gol", name = "Grom'gol", m = 1434, x = 32.5, y = 29.4 },
    { key = "Booty Bay", name = "Booty Bay", m = 1434, x = 26.9, y = 77.1 },
    { key = "Revantusk", name = "Revantusk Village", m = 1425, x = 81.7, y = 81.8 },
    { key = "Stonard", name = "Stonard", m = 1435, x = 46.1, y = 54.8 },
    { key = "Light's Hope", name = "Light's Hope Chapel", m = 1423, x = 70.5, y = 47.5 },
    { key = "Flame Crest", name = "Flame Crest", m = 1428, x = 65.7, y = 24.2 },
    { key = "Orgrimmar", name = "Orgrimmar", m = 1454, x = 45.1, y = 63.9 },
    { key = "Thunder Bluff", name = "Thunder Bluff", m = 1456, x = 47.0, y = 49.8 },
    { key = "Crossroads", name = "The Crossroads", m = 1413, x = 51.5, y = 30.3 },
    { key = "Ratchet", name = "Ratchet", m = 1413, x = 63.1, y = 37.2 },
    { key = "Taurajo", name = "Camp Taurajo", m = 1413, x = 44.5, y = 59.1 },
    { key = "Sun Rock", name = "Sun Rock Retreat", m = 1442, x = 45.1, y = 59.8 },
    { key = "Freewind", name = "Freewind Post", m = 1441, x = 45.1, y = 49.1 },
    { key = "Shadowprey", name = "Shadowprey Village", m = 1443, x = 21.6, y = 74.1 },
    { key = "Gadgetzan", name = "Gadgetzan", m = 1446, x = 51.6, y = 25.4 },
    { key = "Mojache", name = "Camp Mojache", m = 1444, x = 75.5, y = 44.4 },
    { key = "Valormok", name = "Valormok", m = 1447, x = 22.0, y = 49.6 },
    { key = "Marshal", name = "Marshal's Refuge", m = 1449, x = 45.2, y = 5.8 },
    { key = "Everlook", name = "Everlook", m = 1452, x = 60.5, y = 36.3 },
    { key = "Brackenwall", name = "Brackenwall Village", m = 1445, x = 35.6, y = 31.9 },
    { key = "Bloodvenom", name = "Bloodvenom Post", m = 1448, x = 34.4, y = 54.0 },
    { key = "Zoram", name = "Zoram'gar Outpost", m = 1440, x = 12.2, y = 33.8 },
    { key = "Splintertree", name = "Splintertree Post", m = 1440, x = 73.2, y = 61.6 },
    { key = "Moonglade", name = "Moonglade", m = 1450, x = 32.1, y = 66.6 },
    { key = "Cenarion Hold", name = "Cenarion Hold", m = 1451, x = 48.7, y = 36.7 },
    { key = "Rog'mar", name = "Rog'mar", m = -16591, x = 58.1, y = 42.6 },
}
