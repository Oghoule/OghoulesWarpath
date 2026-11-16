-- Oghoule's Warpath : quetes de metier (GENERE par profq.py). s = metier (skillLine), m = niveau de metier requis,
-- r = niveau requis, l = niveau de la quete, q = quete (fin de chaine), x = choix de specialisation, d = en donjon.
local ADDON, ns = ...
ns.ProfQuests = {
    { s = 129, m = 1, r = 4, l = 6, q = 97903 }, -- Camping 101: First Aid
    { s = 129, m = 1, r = 4, l = 6, q = 97931 }, -- Camping 101: First Aid
    { s = 129, m = 1, r = 4, l = 6, q = 97955 }, -- Camping 101: First Aid
    { s = 129, m = 1, r = 4, l = 6, q = 97965 }, -- Camping 101: First Aid
    { s = 129, m = 225, r = 35, l = 45, q = 6622 }, -- Triage
    { s = 164, m = 1, r = 4, l = 6, q = 97900 }, -- Camping 101: Blacksmithing
    { s = 164, m = 1, r = 4, l = 6, q = 97928 }, -- Camping 101: Blacksmithing
    { s = 164, m = 1, r = 4, l = 6, q = 97952 }, -- Camping 101: Blacksmithing
    { s = 164, m = 1, r = 4, l = 6, q = 97964 }, -- Camping 101: Blacksmithing
    { s = 164, m = 1, r = 6, l = 10, q = 96874 }, -- This Is Spinal Axe
    { s = 164, m = 1, r = 32, l = 36, q = 2755 }, -- Joys of Omosh
    { s = 164, m = 210, r = 40, l = 45, q = 2765 }, -- Expert Blacksmith!
    { s = 164, m = 210, r = 40, l = 50, q = 3321, d = 1 }, -- Did You Lose This?
    { s = 164, m = 200, r = 40, l = 40, q = 5301, x = 1 }, -- The Art of the Armorsmith
    { s = 164, m = 200, r = 40, l = 40, q = 5302, x = 1 }, -- The Way of the Weaponsmith
    { s = 164, m = 250, r = 50, l = 60, q = 5305, d = 1 }, -- Sweet Serenity
    { s = 164, m = 250, r = 50, l = 60, q = 5306, d = 1 }, -- Snakestone of the Shadow Huntress
    { s = 164, m = 250, r = 50, l = 60, q = 5307, d = 1 }, -- Corruption
    { s = 164, m = 270, r = 55, l = 60, q = 5103 }, -- Hot Fiery Death
    { s = 164, m = 270, r = 55, l = 60, q = 5127, d = 1 }, -- The Demon Forge
    { s = 165, m = 10, r = 4, l = 10, q = 769 }, -- Kodo Hide Bag
    { s = 165, m = 1, r = 4, l = 6, q = 97906 }, -- Camping 101: Leatherworking
    { s = 165, m = 1, r = 4, l = 6, q = 97934 }, -- Camping 101: Leatherworking
    { s = 165, m = 1, r = 4, l = 6, q = 97958 }, -- Camping 101: Leatherworking
    { s = 165, m = 1, r = 4, l = 6, q = 97969 }, -- Camping 101: Leatherworking
    { s = 165, m = 1, r = 6, l = 10, q = 96875 }, -- Beasts of Thunder Ridge
    { s = 165, m = 225, r = 40, l = 55, q = 5145, x = 1 }, -- Dragonscale Leatherworking
    { s = 165, m = 225, r = 40, l = 55, q = 5146, x = 1 }, -- Elemental Leatherworking
    { s = 165, m = 225, r = 40, l = 55, q = 5148, x = 1 }, -- Tribal Leatherworking
    { s = 171, m = 1, r = 4, l = 6, q = 97899 }, -- Camping 101: Alchemy
    { s = 171, m = 1, r = 4, l = 6, q = 97927 }, -- Camping 101: Alchemy
    { s = 171, m = 1, r = 4, l = 6, q = 97951 }, -- Camping 101: Alchemy
    { s = 171, m = 1, r = 4, l = 6, q = 97963 }, -- Camping 101: Alchemy
    { s = 171, m = 210, r = 40, l = 44, q = 2203 }, -- Badlands Reagent Run II
    { s = 182, m = 1, r = 4, l = 6, q = 97905 }, -- Camping 101: Herbalism
    { s = 182, m = 1, r = 4, l = 6, q = 97933 }, -- Camping 101: Herbalism
    { s = 182, m = 1, r = 4, l = 6, q = 97957 }, -- Camping 101: Herbalism
    { s = 182, m = 1, r = 4, l = 6, q = 97968 }, -- Camping 101: Herbalism
    { s = 182, m = 1, r = 9, l = 16, q = 866 }, -- Root Samples
    { s = 185, m = 15, r = 15, l = 23, q = 862 }, -- Dig Rat Stew
    { s = 185, m = 1, r = 28, l = 31, q = 7321 }, -- Soothing Turtle Bisque
    { s = 185, m = 225, r = 35, l = 45, q = 6610 }, -- Clamlette Surprise
    { s = 185, m = 285, r = 54, l = 57, q = 8317 }, -- Kitchen Assistance
    { s = 186, m = 1, r = 4, l = 6, q = 97907 }, -- Camping 101: Mining
    { s = 186, m = 1, r = 4, l = 6, q = 97935 }, -- Camping 101: Mining
    { s = 186, m = 1, r = 4, l = 6, q = 97959 }, -- Camping 101: Mining
    { s = 186, m = 1, r = 4, l = 6, q = 97970 }, -- Camping 101: Mining
    { s = 186, m = 230, r = 40, l = 55, q = 4083, d = 1 }, -- The Spectral Chalice
    { s = 197, m = 1, r = 4, l = 6, q = 96102 }, -- Camping 101: Tailoring
    { s = 197, m = 1, r = 4, l = 6, q = 97937 }, -- Camping 101: Tailoring
    { s = 197, m = 1, r = 4, l = 6, q = 97961 }, -- Camping 101: Tailoring
    { s = 197, m = 1, r = 4, l = 6, q = 97972 }, -- Camping 101: Tailoring
    { s = 197, m = 230, r = 43, l = 50, q = 3402 }, -- The Undermarket
    { s = 197, m = 280, r = 50, l = 55, q = 6032 }, -- Sacred Cloth
    { s = 202, m = 1, r = 4, l = 6, q = 97902 }, -- Camping 101: Engineering
    { s = 202, m = 1, r = 4, l = 6, q = 97930 }, -- Camping 101: Engineering
    { s = 202, m = 1, r = 4, l = 6, q = 97954 }, -- Camping 101: Engineering
    { s = 202, m = 1, r = 4, l = 6, q = 98285 }, -- Camping 101: Engineering
    { s = 202, m = 200, r = 30, l = 47, q = 3639, x = 1 }, -- Show Your Work
    { s = 202, m = 200, r = 30, l = 47, q = 3643, x = 1 }, -- Show Your Work
    { s = 333, m = 1, r = 4, l = 6, q = 97901 }, -- Camping 101: Enchanting
    { s = 333, m = 1, r = 4, l = 6, q = 97929 }, -- Camping 101: Enchanting
    { s = 333, m = 1, r = 4, l = 6, q = 97953 }, -- Camping 101: Enchanting
    { s = 333, m = 1, r = 4, l = 6, q = 98284 }, -- Camping 101: Enchanting
    { s = 333, m = 1, r = 5, l = 8, q = 96873 }, -- A Pain in the Neck
    { s = 356, m = 1, r = 4, l = 6, q = 97904 }, -- Camping 101: Fishing
    { s = 356, m = 1, r = 4, l = 6, q = 97932 }, -- Camping 101: Fishing
    { s = 356, m = 1, r = 4, l = 6, q = 97956 }, -- Camping 101: Fishing
    { s = 356, m = 1, r = 4, l = 6, q = 97967 }, -- Camping 101: Fishing
    { s = 356, m = 225, r = 35, l = 45, q = 6607 }, -- Nat Pagle, Angler Extreme
    { s = 393, m = 1, r = 4, l = 8, q = 768 }, -- Gathering Leather
    { s = 393, m = 1, r = 4, l = 6, q = 97908 }, -- Camping 101: Skinning
    { s = 393, m = 1, r = 4, l = 6, q = 97936 }, -- Camping 101: Skinning
    { s = 393, m = 1, r = 4, l = 6, q = 97960 }, -- Camping 101: Skinning
    { s = 393, m = 1, r = 4, l = 6, q = 97971 }, -- Camping 101: Skinning
}
