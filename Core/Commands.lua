-- Oghoule's Warpath : moteur (Commands.lua) - voir Core.lua
local ADDON, ns = ...
local _ENV = ns.CoreEnv
if setfenv then setfenv(1, _ENV) end

------------------------------------------------------------------
-- Commandes
------------------------------------------------------------------
function ListGuides()
    local keys = {}
    for k in pairs(Guides) do if not IS_DUNGEON[k] then keys[#keys + 1] = k end end
    table.sort(keys)
    for _, k in ipairs(keys) do
        say(string.format("  %s%s - %s", k, k == DB.guide and T("active") or "", Title(Guides[k])))
    end
    say(T("dList"))
    say(T("guideHelp"))
end

SLASH_WARPATH1 = "/warpath"
SLASH_WARPATH2 = "/hg"
SLASH_WARPATH3 = "/wpath"
SlashCmdList["WARPATH"] = function(msg)
    if not DB or not f then return end
    local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "toggle" then
        ShowGuide(DB.shown == false)
    elseif cmd == "compact" or cmd == "mini" then
        ToggleMini()
    elseif cmd == "intendance" or cmd == "quartermaster" or cmd == "qm" then
        if arg == "stop" or arg == "quitter" or arg == "quit" then QMQuit() else QMOpen() end
    elseif cmd == "skip" or cmd == "ignore" then
        Ignore()
    elseif cmd == "unskip" then
        if arg == "all" or arg == "tout" then
            wipe(DB.ignored); wipe(DB.seen); say(T("unskipAll"))
        elseif tonumber(arg) then
            DB.ignored[tonumber(arg)] = nil; say(T("unskipOne", arg))
        else
            local list = {}
            for id in pairs(DB.ignored) do list[#list + 1] = tostring(id) end
            table.sort(list)
            say(T("ignoredList", #list > 0 and table.concat(list, ", ") or T("none")))
            say(T("unskipHelp"))
        end
        Advance(); Refresh(true)
    elseif cmd == "next" then
        Peek(1)
    elseif cmd == "prev" then
        Peek(-1)
    elseif cmd == "now" or cmd == "sync" then
        peek = nil; if optCache then optCache.key = nil end; Advance(); Refresh(true)
        if steps then
            if current > #steps then say(T("doneByQuests", Title(G)))
            else say(T("stepNow", current, #steps)) end
        end
    elseif cmd == "trajet" or cmd == "route" then
        -- detail du trajet vers l'etape affichee : a pied (chemin reel) contre le meilleur vol connu
        local st = steps and steps[peek or focus or current]
        local here = PlayerWP()
        local dest = st and st.m and st.x and WP(st.m, st.x, st.y)
        if not (here and dest) then say(T("routeNone")); return end
        if here[3] ~= dest[3] then say(T("routeOther")); return end
        local walk = Walk(here, dest)
        local fl, c = BestFlight(here, dest, (DB.useFlights ~= false) and KnownFlights() or {})
        say(T("routeWalk", math.floor(walk / RUN / 60 + 0.5), math.floor(Dist(here[1], here[2], dest[1], dest[2]) + 0.5)))
        if fl then say(T("routeFly", fl.from.name, fl.to.name, math.floor(c / RUN / 60 + 0.5)))
        else say(T("routeNoFly")) end
    elseif cmd == "goto" then
        local n = tonumber(arg)
        if steps and n and n >= 1 and n <= #steps then
            peek = (n ~= current) and n or nil; Refresh(true)
        else
            say(T("gotoHelp"))
        end
    elseif cmd == "guide" then
        if arg == "" then ListGuides()
        elseif arg:lower() == "auto" then
            DB.manual = nil
            local k = AutoPick()
            if k then SetGuide(k) end
        elseif IS_DUNGEON[arg:lower()] then StartDungeon(arg:lower())
        elseif SetGuide(arg:lower()) then DB.manual = true
        else say(T("unknownGuide", arg)); ListGuides() end
    elseif cmd == "options" or cmd == "config" or cmd == "o" then
        ns.UI.ToggleOptions()
    elseif cmd == "lang" or cmd == "langue" or cmd == "language" then
        local l = arg:lower()
        if l == "fr" or l == "en" then ns.UI.SetLang(l) else ns.UI.SetLang(Lang() == "fr" and "en" or "fr") end
    elseif cmd == "minimap" then
        DB.mmHide = not DB.mmHide
        if ns.UI.mm then ns.UI.mm:SetShown(not DB.mmHide) end
        say(DB.mmHide and T("mmHidden") or T("mmShown"))
    elseif cmd == "donjon" or cmd == "dungeon" or cmd == "d" then
        local a = arg:lower()
        if a == "" then ListDungeons()
        elseif a == "stop" then StopDungeon()
        elseif a == "reset" then wipe(DB.dAnswer); wipe(DB.dLater); say(T("dReset")); CheckDungeons()
        elseif IS_DUNGEON[a] then StartDungeon(a)
        else say(T("unknownDungeon", arg)); ListDungeons() end
    elseif cmd == "wp" then
        DB.wp = not DB.wp
        if not DB.wp then ClearWaypoint() end
        lastWP = nil
        Refresh(true)
        say(DB.wp and T("wpOn") or T("wpOff"))
    elseif cmd == "here" then
        local zone = GetRealZoneText and GetRealZoneText() or "?"
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local pos = mapID and ns.MapAPI.PlayerPos(mapID, "player")
        if pos then
            local x, y = pos:GetXY()
            say(T("here", zone, x * 100, y * 100, mapID))
        else
            say(T("noPos", zone))
        end
    elseif cmd == "bug" and arg == "" and BugWindow then
        BugWindow()
    elseif cmd == "bug" then
        -- signalement : enregistre ou tu en es (envoie ensuite le fichier WTF\Account\...\SavedVariables\OghoulesWarpath.lua)
        local g = DB.guide
        local i = g and DB.step[g]
        local s = g and Guides[g] and i and Guides[g].steps[i]
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local pos = mapID and ns.MapAPI.PlayerPos(mapID, "player")
        local x, y = 0, 0
        if pos then x, y = pos:GetXY() end
        WarpathDropDB._bugs = WarpathDropDB._bugs or {}
        local b = WarpathDropDB._bugs
        if #b >= 100 then table.remove(b, 1) end
        b[#b + 1] = { when = date and date("%Y-%m-%d %H:%M") or "", v = VERSION, guide = g, step = i,
            id = s and s.id, text = s and StepText(s), map = mapID, x = math.floor(x * 1000) / 10, y = math.floor(y * 1000) / 10,
            lvl = UnitLevel("player"), race = myRace, class = myClass, note = arg ~= "" and arg or nil }
        say(T("bugSaved", #b))
    elseif cmd == "chemin" or cmd == "path" or cmd == "trail" then
        TrailCmd(arg)
    elseif cmd == "passage" or cmd == "pass" then
        PassageCmd(arg)
    elseif cmd == "diag" and arg ~= "plus" and arg ~= "more" then
        -- version courte : ce qui sert a comprendre un souci en jeu (grotte, position, specialisation)
        local function yn(v) return v and ("|cff9cc7a8" .. T("yes") .. "|r") or ("|cffc24a3e" .. T("no") .. "|r") end
        local zone = G and Title(G):gsub("%s*%b()", ""):gsub("%s+%d+%-%d+$", "") or "?"
        say(T("dgxHead", VERSION, zone, current or 0, steps and #steps or 0))
        local c = CaveDiag and CaveDiag() or {}
        say("|cffcdbb8e" .. T("dgxCave") .. "|r")
        say("   " .. T("dgxWhere", c.indoors and ("|cff9cc7a8" .. T("diagIn") .. "|r") or T("diagOut")))
        say("   " .. T("dgxCaveStep", yn(c.cave)))
        if c.cave then
            if c.entry then
                say("   " .. T("dgxEntry", yn(true), c.dist and T("dist", c.dist) or "?", T(c.own and "dgxByYou" or "dgxByOthers")))
            else
                say("   " .. T("dgxEntry", yn(false), "-", T("dgxLearn")))
            end
        end
        if c.indoors then say("   " .. T("dgxExit", yn(c.exitKnown))) end
        local AIM = { pass = "dgxAimPass", zone = "dgxAimZone", enter = "dgxAimEnter", exit = "dgxAimExit", obj = "dgxAimObj", corpse = "dgxAimCorpse", step = "dgxAimStep" }
        say("   " .. T("dgxAim", T(AIM[c.aim] or "dgxAimStep")))
        local pm, px, py = PlayerPos()
        say(T("dgxPos", MAPNAME[pm] or tostring(pm), px and string.format("%.1f, %.1f", px, py) or "?"))
        local spec = MySpec and MySpec()
        say(T("dgxSpec", tostring(spec or "?"), math.floor((KillTime()) + 0.5)))
        say("|cff8c7f62" .. T("dgxMore") .. "|r")
    elseif cmd == "diag" then
        -- version complete (/warpath diag plus) : API du jeu, talents, donnees
        -- ce que le jeu fournit a l'addon (pour verifier ce qui marche sur Forever)
        local function yn(v) return v and "|cff9cc7a8OK|r" or "|cffc24a3eNON|r" end
        local okS, sp = pcall(function() return GetSpecialization and GetSpecialization() end)
        local okT, tab = pcall(function()
            if not GetTalentTabInfo then return "absente" end
            local r = { GetTalentTabInfo(1) }
            for k = 1, math.min(#r, 6) do r[k] = tostring(r[k]) end
            return table.concat(r, "|", 1, math.min(#r, 6))
        end)
        local apis = {}
        for _, n in ipairs({ "GetNumTalentTabs", "GetTalentInfo", "GetSpecializationInfo", "IsPlayerSpell" }) do apis[#apis + 1] = n .. "=" .. (_G[n] and "oui" or "non") end
        for _, n in ipairs({ "C_ClassTalents", "C_Traits", "C_SpecializationInfo", "C_Talent" }) do apis[#apis + 1] = n .. "=" .. (_G[n] and "oui" or "non") end
        say("API talents : " .. table.concat(apis, ", "))
        local okC2, cs = pcall(function() return C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization() end)
        local trees, why = TraitTrees()
        local tl = {}
        for t, tr in ipairs(trees or {}) do tl[#tl + 1] = t .. ":" .. tostring(tr.id) .. " (" .. tr.n .. " noeuds, " .. tr.spent .. " pts)" end
        say("C_SpecializationInfo=" .. tostring(okC2 and cs) .. " ; traits " .. tostring(why) .. " ; arbres " .. (#tl > 0 and table.concat(tl, ", ") or "aucun"))
        local spec = MySpec and MySpec()
        say(T("diagHead", VERSION))
        say(T("diagSpec", tostring(okS and sp), tostring(okT and tab), tostring(spec), math.floor((KillTime()) + 0.5)))
        local indoors = IsIndoors and IsIndoors()
        local pm, px, py = PlayerPos()
        say(T("diagPos", tostring(pm), px and string.format("%.1f, %.1f", px, py) or "?", indoors and T("diagIn") or T("diagOut"),
            yn(PlayerWP() ~= nil)))
        local s = steps and steps[current]
        local q = s and Ids(s)[1]
        local objs = q and C_QuestLog and C_QuestLog.GetQuestObjectives and select(2, pcall(C_QuestLog.GetQuestObjectives, q))
        local o1 = type(objs) == "table" and objs[1]
        say(T("diagQuest", tostring(q), o1 and (tostring(o1.text) .. " " .. tostring(o1.numFulfilled) .. "/" .. tostring(o1.numRequired)) or "-",
            yn(C_Item and C_Item.GetItemCount)))
        local own = WarpathDropDB and WarpathDropDB._caves or {}
        local nC = 0; for _, v in pairs(own) do if type(v) == "table" then nC = nC + 1 end end
        local nB = 0; for _ in pairs(ns.BakedCaves or {}) do nB = nB + 1 end
        local wm = 0; for _ in pairs((ns.ClassTrainers or {}).WEAPON or {}) do wm = wm + 1 end
        say("Objet de l'étape : " .. tostring(ns.Comfort and ns.Comfort.ItemDiag and select(2, pcall(ns.Comfort.ItemDiag))))
        say(T("diagData", nC, nB, wm, (GetLocale and GetLocale()) or "?", Lang()))
    elseif cmd == "classe" or cmd == "class" then
        local list = ClassQuestList()
        local n = tonumber(arg)
        if n and list[n] and list[n].q and not list[n].done then AskChain(list[n].q, true); return end
        if #list == 0 then say(T("classNone")); return end
        for k, c in ipairs(list) do
            say(string.format("  %d. %s%s (%s)|r%s", k, c.done and "|cff8c7f62" or "|cffcdbb8e", c.name, c.lvl2 > c.lvl and (c.lvl .. "-" .. c.lvl2) or tostring(c.lvl), c.done and (" - " .. T("classDone")) or ""))
        end
    elseif cmd == "tuto" or cmd == "tutorial" or cmd == "visite" or cmd == "tour" then
        ShowTutorial(true)
    elseif cmd == "news" or cmd == "nouveautes" or cmd == "quoi" then
        if not ShowNews(true) then say(T("newsNone")) end
    elseif cmd == "chronique" or cmd == "chronicle" or cmd == "chron" then
        ChronShow(arg == "now" and 0 or nil)
    elseif cmd == "apercu" or cmd == "aperçu" or cmd == "preview" then
        -- v1.42 : montre tout de suite la banniere de la Chronique et le « Quoi de neuf » (fondus, reflet),
        -- sans rien changer aux sauvegardes
        if not (ChronPreview and ChronPreview()) then say(T("chPreviewNone")) end
        Toast(T("popNews"), T("newsToast", VERSION), function() ShowNews(true) end)
    elseif cmd == "pvp" then
        PvPReport(arg)
    elseif cmd == "temps" or cmd == "time" or cmd == "xp" then
        JournalReport((arg or ""):lower())
    elseif cmd == "partage" or cmd == "share" then
        if arg == "off" then WarpathDropDB._share = false elseif arg == "on" then WarpathDropDB._share = true end
        local np = 0
        for _ in pairs(WarpathDropDB._from or {}) do np = np + 1 end
        say(T("shareState", ns.ShareOn() and T("shareOn") or T("shareOff"), np))
    elseif cmd == "reset" then
        wipe(DB.ignored); wipe(DB.seen); wipe(DB.done); DB.manual = nil
        local k = AutoPick()
        if k then SetGuide(k) end
        say(T("resetDone"))
    else
        say(T("cmds"))
    end
end

------------------------------------------------------------------
-- Raccourcis clavier (Echap > Raccourcis > AddOns > Oghoule's Warpath) : voir Bindings.xml
------------------------------------------------------------------
-- v1.41 : pendant une commande /warpath, les messages s'affichent toujours (meme si le chat est reduit)
do
    local raw = SlashCmdList["WARPATH"]
    SlashCmdList["WARPATH"] = function(msg)
        inCommand = true
        local ok, err = pcall(raw, msg)
        inCommand = false
        if not ok then say(T("errInternal", tostring(err)), "error") end
    end
end

_G.BINDING_HEADER_WARPATH = "Oghoule's Warpath"
_G.BINDING_NAME_WARPATH_OK = "Valider / passer l'étape"
_G.BINDING_NAME_WARPATH_PREV = "Voir l'étape précédente"
_G.BINDING_NAME_WARPATH_NEXT = "Voir l'étape suivante"
_G.BINDING_NAME_WARPATH_TOGGLE = "Afficher / cacher le guide"
_G.BINDING_NAME_WARPATH_OPTIONS = "Ouvrir les options"
_G.BINDING_NAME_WARPATH_NOW = "Revenir à l'étape actuelle"
_G.BINDING_NAME_WARPATH_MINI = "Mode compact / normal"
_G["BINDING_NAME_CLICK WarpathTarget1:LeftButton"] = "Cibler la 1re cible de l'étape"
_G["BINDING_NAME_CLICK WarpathTarget2:LeftButton"] = "Cibler la 2e cible de l'étape"
_G.WarpathBinding = function(action)
    if action == "ok" then Ignore()
    elseif action == "prev" then Peek(-1)
    elseif action == "next" then Peek(1)
    elseif action == "now" then BackToNow()
    elseif action == "toggle" then SlashCmdList.WARPATH("toggle")
    elseif action == "mini" then ToggleMini()
    elseif action == "options" then SlashCmdList.WARPATH("options") end
end

-- Premier lancement : courte presentation
-- Quoi de neuf : les nouveautes depuis la derniere version que tu as vue (une fois par compte)
local NEWS = {
    { v = "1.45", fr = "Vols : plus de vol automatique, le carré vert sur la carte des vols montre la destination conseillée. Ce conseil est recalculé après la lecture de la carte (avant, Ratchet pouvait t'envoyer à Brackenwall au lieu de Camp Taurajo pour RFK) et pendant que tu marches. Un vol déjà conseillé reste tant qu'il fait gagner du temps : le guide ne change plus d'avis en chemin.",
      en = "Flights: no more automatic flights; the green square on the flight map shows the suggested destination. This advice is now recalculated after the flight map is read (before, Ratchet could send you to Brackenwall instead of Camp Taurajo for RFK) and while you walk. A flight already suggested stays as long as it saves time: the guide no longer changes its mind on the way." },
    { v = "1.45", fr = "Ashenvale : l'escorte de Vorsha the Lasher passe avant les nagas (faite après, elle échoue), et pour Troll Charm le guide t'envoie directement dans la grotte Thistlefur Hold, où tout se fait d'un coup avant l'escorte de Ruul. Si la quête de l'étape échoue (escorte ratée), le guide te dit de l'abandonner et de la reprendre. Pour revenir à une étape passée : /warpath unskip. En combat, le repère du jeu sur la carte attend la fin du combat pour changer : fini les messages rouges « action bloquée (SetPassThroughButtons) ».",
      en = "Ashenvale: the Vorsha the Lasher escort now comes before the naga (done after, it fails), and for Troll Charm the guide sends you straight into the Thistlefur Hold cave, where it's all done in one go before Ruul's escort. If the step's quest fails (failed escort), the guide tells you to abandon it and pick it up again. To go back to a skipped step: /warpath unskip. In combat, the game's map marker waits until the fight ends to move: no more red \"action blocked (SetPassThroughButtons)\" messages." },
    { v = "1.45", fr = "Options, onglet Campagne : une seule liste de zones sur deux colonnes, qui tient sur une page. Les zones finies et trop basses sont masquées (une case en bas les fait revenir). La colonne « Zone suivante » est retirée : à la fin d'une zone, le guide te propose toujours la suivante.",
      en = "Options, Campaign tab: a single list of zones in two columns that fits on one page. Completed and too-low zones are hidden (a box at the bottom brings them back). The \"Next zone\" column is gone: at the end of a zone, the guide still offers you the next one." },
    { v = "1.45", fr = "Options : un fin contour doré, qui pulse doucement, entoure ce qui est à ton niveau : les zones (Campagne), les donjons où il te reste des quêtes, et les quêtes de classe et de métier que tu peux commencer maintenant.",
      en = "Options: a thin, softly pulsing gold frame surrounds what is at your level: zones (Campaign), dungeons where you still have quests, and the class and profession quests you can start right now." },
    { v = "1.45", fr = "Donjons : si tu meurs dans le donjon, la flèche te ramène à son entrée, et une résurrection auprès de l'ange ne ferme plus le journal du donjon. Chemins gardés : la flèche ne te fait plus refaire un chemin à l'envers quand l'objectif est ailleurs. Thunder Bluff : quand un vol est plus rapide (vers Ratchet par exemple), la flèche ne t'envoie plus à l'ascenseur. Les quêtes « d'appel » (comme Trouble in the Deeps chez Tsunaman) sont sautées si tu as déjà la quête vers laquelle elles t'envoient : le PNJ ne te les propose plus. L'étape d'entrée dit maintenant « Aller à Blackfathom Deeps » au lieu de « Aller ». PvP : une même victoire ne met plus deux X sur la carte. Ashenvale : l'étape du Warsong Outrider explique qu'il faut lui parler pour recevoir sa quête.",
      en = "Dungeons: if you die in the dungeon, the arrow leads you back to its entrance, and resurrecting at the spirit healer no longer closes the dungeon log. Saved paths: the arrow no longer makes you walk a path backwards when the objective is elsewhere. Thunder Bluff: when a flight is faster (to Ratchet for example), the arrow no longer sends you to the elevator. \"Breadcrumb\" quests (like Trouble in the Deeps from Tsunaman) are skipped if you already have the quest they lead to: the NPC no longer offers them. The entrance step now says \"Go to Blackfathom Deeps\" instead of just \"Go\". PvP: a single kill no longer puts two X on the map. Ashenvale: the Warsong Outrider step explains that you talk to him to get his quest." },
    { v = "1.45", fr = "Données de Questie mises à jour (QuestieDB 1.1.4) : niveaux requis plus bas pour quelques quêtes (Durotar, Silverpine, Thousand Needles), Valuable Vantages (Hillsbrad) avec ses 3 points à visiter. Zephras Isle : la chaîne Skyborne reste complète.",
      en = "Questie data updated (QuestieDB 1.1.4): lower required levels for a few quests (Durotar, Silverpine, Thousand Needles), Valuable Vantages (Hillsbrad) with its 3 points to visit. Zephras Isle: the Skyborne chain stays complete." },
    { v = "1.44", fr = "Badlands : niveau 49 conseillé (au lieu de 50) ; Hierophant Theodora Mulvadania est indiquée « 30 m au sud de l'auberge ». Données Questie à jour partout : Palah Thunderhoof (Mulgore) au bon endroit, quelques objets de quête au sol mieux placés, et 3 quêtes de plus dans la liste des quêtes proposées que le guide ne prend pas.",
      en = "Badlands: level 49 recommended (instead of 50); Hierophant Theodora Mulvadania is marked \"30 m south of the inn\". Questie data up to date everywhere: Palah Thunderhoof (Mulgore) in the right place, a few ground quest objects better placed, and 3 more quests in the list of nearby quests the guide skips." },
    { v = "1.43", fr = "Fenêtre du guide : la petite flèche du bloc destination tourne maintenant vers l'endroit où aller, comme la grande flèche (même si la grande est coupée dans les options). Son intérieur rougit doucement quand tu vas dans la bonne direction.",
      en = "Guide window: the small arrow in the destination block now turns toward where you need to go, like the big arrow (even if the big one is turned off in the options). Its inside softly turns red when you're heading the right way." },
    { v = "1.43", fr = "Fenêtre des quêtes de classe, de métier et des chaînes plus claire : un titre qui dit de quoi il s'agit (« Quêtes de classe »), le même nom que dans les options, la durée, l'XP et les monstres sur des lignes séparées, et des chances d'obtenir les objets faciles à lire (« environ 1 fois sur 3 »).",
      en = "Clearer window for class quests, profession quests and quest chains: a title that says what it is (\"Class quests\"), the same name as in the options, time, XP and mobs on separate lines, and easy-to-read item chances (\"about 1 in 3\")." },
    { v = "1.43", fr = "Nouvelle visite guidée : en quelques pages, elle te montre chaque partie de la fenêtre du guide, puis la flèche. Elle t'est proposée à la bienvenue, et tu peux la revoir quand tu veux avec /warpath tuto ou dans les options (Affichage). L'aide « ? » rappelle aussi où trouver les options. Et la première fois que la flèche, la fenêtre de ciblage ou le bouton de pierre de foyer apparaissent, une petite bulle t'explique à quoi ils servent.",
      en = "New guided tour: in a few pages, it shows you each part of the guide window, then the arrow. It is offered at the welcome, and you can replay it any time with /warpath tuto or in the options (Display). The \"?\" help also reminds you where to find the options. And the first time the arrow, the targeting window or the hearthstone button appears, a small bubble explains what it does." },
    { v = "1.43", fr = "Burning Steppes & Blasted Lands (50-54) revu : chaîne de Kalaran Windblade dans Searing Gorge (Set Them Ablaze! et la suite), A Taste of Flame et The Rise of the Machines ajoutées, pour environ 40 000 XP de quêtes de plus. Le trajet vers Stonard se fait maintenant à cheval (tu n'avais pas ce point de vol), les quantités des 5 quêtes des Bloodmages sont indiquées et Kum'isha's Endeavors ne te bloque plus. Blackrock Depths : ajout de Disharmony of Flame (Overmaster Pyron), nécessaire pour Disharmony of Fire et The Last Element.",
      en = "Burning Steppes & Blasted Lands (50-54) reworked: Kalaran Windblade's chain in Searing Gorge (Set Them Ablaze! and the rest), A Taste of Flame and The Rise of the Machines added, for about 40,000 more quest XP. The trip to Stonard is now a ride (you didn't have that flight path), the Bloodmages' 5 quests show their amounts, and Kum'isha's Endeavors no longer blocks you. Blackrock Depths: added Disharmony of Flame (Overmaster Pyron), needed for Disharmony of Fire and The Last Element." },
    { v = "1.43", fr = "Données de Questie mises à jour (QuestieDB 1.1.3) : positions de PNJ, XP et prérequis des quêtes. Vorsha the Lasher : la flèche et le ciblage montrent maintenant Vorsha. Mont Hyjal : Stemming the Demon Tide retirée du guide (réservée à l'Alliance).",
      en = "Questie data updated (QuestieDB 1.1.3): NPC positions, quest XP and prerequisites. Vorsha the Lasher: the arrow and targeting now show Vorsha. Mount Hyjal: Stemming the Demon Tide removed from the guide (Alliance only)." },
    { v = "1.43", fr = "Vols : l'addon ne te fait plus marcher longtemps en croyant qu'un vol est impossible. Un point de vol découvert est maintenant relié tout de suite à tes autres points du continent, et une ancienne carte des vols ne bloque plus un vol vers un point appris depuis.",
      en = "Flights: the addon no longer makes you walk a long way thinking a flight is impossible. A newly discovered flight point is now linked right away to your other points on the continent, and an old flight map no longer blocks a flight to a point learned since." },
    { v = "1.43", fr = "Grand détour : la proposition de garder le chemin attend que tu fermes la carte du monde avant de s'effacer. Seul le « x » compte comme un non ; une proposition ratée revient à la séance suivante. Pierre de foyer : le bouton du conseil suit maintenant la fenêtre quand tu la déplaces (hors combat).",
      en = "Big detour: the offer to keep the path now waits until you close the world map before fading. Only the \"x\" counts as a no; a missed offer comes back next session. Hearthstone: the advice button now follows the window when you move it (out of combat)." },
    { v = "1.42", fr = "Leveling 45-55 : 11 quêtes de plus dans les zones déjà visitées (Feralas, Tanaris, Hinterlands, Azshara, Un'Goro, Felwood, Eastern Plaguelands, Winterspring), pour beaucoup moins de farm entre 45 et 50. Aussi : fenêtre de ciblage plus réactive, vol auto annulé si tu fermes la carte, aide de /warpath complète. La Chronique et le « Quoi de neuf » arrivent en fondu (avec un reflet doré pour la Chronique) en haut au centre de l'écran : ils ne cachent plus la minicarte. Boutons « x », « - » et « + » bien centrés dans leur case. Nouveau, fil d'Ariane : quand tu arrives à un objectif après un grand détour (grotte, tunnel, montagne), un message propose de garder ce chemin ; un clic, et la flèche le suivra ensuite, à l'aller comme au retour, pour toutes les quêtes qui mènent là (/warpath chemin pour la liste ou l'effacer). Quêtes de classe (options) : chaque chaîne porte le nom de sa première quête et ses niveaux (ex. Diplomatic Incident, niveaux 18-26, pour le paladin réprouvé) et elle est proposée dès qu'elle devient disponible, et non plus à sa dernière quête ; ajout de The Tarnished (paladin, niveau 9). Donjons : l'onglet Donjons des options affiche un niveau idéal à côté des niveaux min-max (toutes les quêtes prenables, XP complète) ; et après « Quitter le donjon », le guide ne reste plus bloqué sur une quête à prendre ou à rendre à l'intérieur.",
      en = "Levelling 45-55: 11 more quests in zones you already visit (Feralas, Tanaris, Hinterlands, Azshara, Un'Goro, Felwood, Eastern Plaguelands, Winterspring), for much less grinding between 45 and 50. Also: snappier targeting window, auto-flight cancelled if you close the map, complete /warpath help. The Chronicle and \"What's new\" fade in (with a golden shine for the Chronicle) at the top centre of the screen: they no longer cover the minimap. The \"x\", \"-\" and \"+\" buttons are properly centred in their box. New, breadcrumb trail: when you reach an objective after a big detour (cave, tunnel, mountain), a message offers to keep that path; one click and the arrow will follow it from then on, both ways, for every quest that leads there (/warpath path to list or clear them). Class quests (options): each chain shows its first quest's name and its levels (e.g. Diplomatic Incident, levels 18-26, for Forsaken paladins) and is offered as soon as it becomes available, not at the end; added The Tarnished (paladin, level 9). Dungeons: the Dungeons tab of the options shows an ideal level next to the min-max levels (all quests available, full XP); and after \"Leave the dungeon\", the guide no longer gets stuck on a quest to pick up or turn in inside." },
    { v = "1.41", fr = "Intendance : en capitale, choisis tes arrêts (entraîneur de classe, maître d'armes, tes métiers et les autres, banque, aubergiste, hôtel des ventes, maître de vol). L'addon les met dans l'ordre le plus court, la flèche les enchaîne et chaque arrêt se coche quand tu parles au PNJ. Proposée à ta première arrivée dans une capitale (jusqu'au niveau 15), ensuite avec le bouton « Intendance » dans l'en-tête de la fenêtre ou /warpath intendance. Le mode compact marche aussi en donjon (les quêtes du donjon et leur progression). Donjons : le journal se ferme tout seul quand tu es loin de l'entrée (avant, il pouvait rester affiché partout après une sortie en groupe). Prises groupées : la fenêtre dit quelles quêtes manquent, et OK ne saute que celles-là. Corrigé : messages « action bloquée par le jeu » (SetHeight, SetShown, Hide) en combat, causés par le bouton de la pierre de foyer. Le conseil de pierre de foyer se met à jour quand tu te déplaces (il pouvait proposer de rentrer à l'auberge où tu étais déjà). Aussi : une victoire JcJ ne compte plus en double ; le vol automatique marche avec escale ; fenêtres compacte et normale au même endroit ; journal de donjon : une ligne par objectif au clic ; Thunder Bluff : la flèche passe par l'entrée des Pools of Vision et par le haut de l'ascenseur ; /warpath passage ville et /warpath passage grotte ; plus de question pour le maître d'armes (l'Intendance s'en charge) ; titres propres à chaque question ; Trouble at the Docks retirée du guide de Wailing Caverns. Fenêtre allégée : la chaîne et les quêtes bloquées deviennent deux pastilles (détail au survol), « À suivre » montre 2 étapes (+ pour déplier), le lieu tient sur 2 lignes (coordonnées au survol), la hauteur suit le contenu ; le mode compact a son en-tête (nom de la quête, clic = journal) et sa poignée de taille. Réglage « Messages du chat » (tous, importants, aucun). Bouton « ? » : les raccourcis. Les nouveautés s'annoncent dans un bandeau. Icônes de l'addon partout (pierre de foyer, auberge, marchand, cases cochées, bouton du bas). Textes plus lisibles (11 px minimum). Plus de pied : niveau et XP/h au survol de la barre de progression. Toutes les fenêtres ont le même en-tête (options, ciblage, questions, signalement, Intendance), avec « ? » et poignée de taille là où c'est utile ; options réorganisées en sections.",
      en = "Quartermaster: in a capital city, pick your stops (class trainer, weapon master, your professions and the others, bank, innkeeper, auction house, flight master). The addon puts them in the shortest order, the arrow chains them and each stop is ticked when you talk to the NPC. Offered on your first arrival in a capital (up to level 15), then with the \"Quartermaster\" button in the window header or /warpath quartermaster. Compact mode now also works in dungeons (the dungeon quests and their progress). Dungeons: the dungeon log closes by itself once you are far from the entrance (it could stay up everywhere after leaving in a group). Grouped pick-ups: the window says which quests are missing, and OK skips only those. Fixed: \"action blocked by the game\" messages (SetHeight, SetShown, Hide) in combat, caused by the Hearthstone button. The Hearthstone tip updates as you move (it could suggest going back to the inn you were already at). Also: a PvP kill is no longer counted twice; auto-fly works with stopovers; compact and full windows share the same spot; dungeon log: one line per objective when expanded; Thunder Bluff: the arrow goes through the Pools of Vision entrance and the top of the elevator; /warpath passage city and /warpath passage cave; no more weapon master question (the Quartermaster handles it); each question has its own title; Trouble at the Docks removed from the Wailing Caverns guide. Lighter window: the chain and locked quests become two small chips (details on hover), \"Coming up\" shows 2 steps (+ to expand), the place fits on 2 lines (coordinates on hover), the height follows the content; compact mode has its own header (quest name, click = quest log) and resize grip. \"Chat messages\" setting (all, important, none). \"?\" button: the shortcuts. What's new shows up as a banner. Addon icons everywhere (Hearthstone, inn, vendor, checked boxes, bottom button). More readable text (11 px minimum). No more footer: level and XP/h on hover over the progress bar. Every window shares the same header (options, targeting, questions, bug report, Quartermaster), with \"?\" and a resize grip where useful; options reorganized into sections." },
    { v = "1.40", fr = "Mode compact : le « - » en haut à droite de la fenêtre (ou /warpath compact, ou un raccourci clavier) ne garde que les objectifs de l'étape avec leur compteur, ou une seule ligne pour prendre ou rendre une quête. Le « + » ramène la fenêtre complète. La fenêtre complète s'agrandit ou se réduit avec la poignée en bas à droite.",
      en = "Compact mode: the \"-\" at the top right of the window (or /warpath compact, or a key binding) keeps only the step's objectives with their counters, or a single line to pick up or turn in a quest. The \"+\" brings back the full window. The full window grows or shrinks with the grip at the bottom right." },
    { v = "1.39", fr = "Vols : l'addon ne croit plus connaître des points de vol jamais découverts (trajets faux, ex. Sun Rock) et apprend un vol dès que tu le découvres. Le bouton du maître d'armes et les repères d'entraîneurs dirigent maintenant la flèche (puis retour au guide une fois sur place). Orgrimmar, Thunder Bluff et Undercity : la flèche passe par la porte au lieu d'aller à vol d'oiseau.",
      en = "Flights: the addon no longer thinks it knows flight points you never discovered (wrong routes, e.g. Sun Rock) and learns a flight as soon as you discover it. The weapon master button and trainer pins now steer the arrow (then back to the guide once there). Orgrimmar, Thunder Bluff and Undercity: the arrow goes through the gate instead of as the crow flies." },
    { v = "1.38", fr = "Western Plaguelands : All Along the Watchtowers ajoutée (prise à The Bulwark, les 4 tours à marquer pendant le passage à Andorhal).",
      en = "Western Plaguelands: All Along the Watchtowers added (picked up at The Bulwark, the 4 towers marked during the Andorhal visit)." },
    { v = "1.37", fr = "Zephras Isle : la fin de l'histoire est maintenant dans le guide (Desperate Times jusqu'à What Comes Next), sans quoi The Earthen Ring restait bloquée. Style de jeu : une quête qui débloque une quête d'un guide suivant n'est plus jamais sautée.",
      en = "Zephras Isle: the end of the story is now in the guide (Desperate Times through What Comes Next); without it The Earthen Ring stayed locked. Play style: a quest that unlocks a quest in a later guide is never skipped." },
    { v = "1.36", fr = "Étapes « Monte au niveau » : la flèche et le bloc destination indiquent un coin de farm près de toi, avec des monstres de ton niveau (Manque d'XP : Farmer ou Les deux). « Les deux » propose aussi le donjon de ton niveau.",
      en = "\"Reach level\" steps: the arrow and destination block show a farm spot near you with mobs of your level (Missing XP: Grind or Both). \"Both\" also suggests the dungeon for your level." },
    { v = "1.35", fr = "Cibles de l'objectif : le taux de drop est toujours aligné au bord droit de la fenêtre.",
      en = "Objective targets: the drop rate is always aligned to the right edge of the window." },
    { v = "1.34", fr = "Cibles de l'objectif : poignée en bas à droite pour changer la largeur de la fenêtre (hors combat). La largeur est gardée.",
      en = "Objective targets: grip at the bottom right to change the window width (out of combat). The width is kept." },
    { v = "1.33", fr = "Un seul XP/h : le rythme actif, dans le pied de la fenêtre, avec le temps avant le niveau suivant (détail au survol). La ligne de rythme du haut est retirée. Le badge indique le niveau de la QUÊTE, coloré selon la difficulté.",
      en = "A single XP/h: the active pace, in the window footer, with the time to the next level (details on hover). The pace line at the top is removed. The badge shows the QUEST level, colored by difficulty." },
    { v = "1.32", fr = "Données de Questie mises à jour (QuestieDB 1.1.2) : positions de PNJ et de monstres, XP des quêtes, nouvelles quêtes 53-60, itinéraire de Zephras Isle recalculé (toujours réservé aux Skyborne).",
      en = "Questie data updated (QuestieDB 1.1.2): NPC and mob positions, quest XP, new 53-60 quests, Zephras Isle route recalculated (still Skyborne only)." },
    { v = "1.31", fr = "Nouvelle commande /warpath passage : place-toi à l'entrée d'un tunnel, d'une rampe ou d'un pont et tape-la ; la flèche passera par là pour l'étape affichée tant que tu es du mauvais côté (efface pour retirer, liste pour voir les tiens). Drygulch Ravine : la flèche repasse aussi par le tunnel pour rendre Securing the Lines.",
      en = "New /warpath passage command: stand at a tunnel, ramp or bridge entrance and type it; the arrow will go through there for the shown step while you're on the wrong side (clear to remove, list to see yours). Drygulch Ravine: the arrow also goes back through the tunnel to turn in Securing the Lines." },
    { v = "1.30", fr = "Flèche de camp en camp (10 quêtes, ex. Encroachment) : elle revient vers le camp qui reste à faire. Rendre une quête : si le même PNJ en donne d'autres, la fenêtre affiche « Puis reparle-lui pour prendre ». Conseil de pierre de foyer : clic sur l'icône pour l'utiliser.",
      en = "Camp-to-camp arrow (10 quests, e.g. Encroachment): it comes back toward the camp still to do. Turning in a quest: if the same NPC gives others, the window shows \"Then talk to them again to pick up\". Hearthstone tip: click the icon to use it." },
    { v = "1.29", fr = "Securing the Lines : la flèche passe d'abord par l'entrée du tunnel de Drygulch Ravine, puis vise le ravin une fois traversé.",
      en = "Securing the Lines: the arrow first goes to the Drygulch Ravine tunnel entrance, then to the ravine once you're through." },
    { v = "1.28", fr = "/warpath diag simplifié : dedans ou dehors, étape de grotte, entrée connue (et par qui), sortie mémorisée, ce que vise la flèche, position et spécialisation. Les détails techniques sont dans /warpath diag plus.",
      en = "Simpler /warpath diag: indoors or outdoors, cave step, known entrance (and who learned it), remembered exit, what the arrow points to, position and specialization. Technical details are in /warpath diag plus." },
    { v = "1.27", fr = "Carte du monde : erreur au chargement corrigée (« Tous les métiers » restait vide et « Entraîneurs de métier » changeait de taille au premier clic).",
      en = "World map: load error fixed (\"All professions\" stayed empty and \"Profession trainers\" changed size on the first click)." },
    { v = "1.26", fr = "Boutons de la carte regroupés dans une seule barre : même taille pour tous (plus petits sur la carte réduite), cases bien affichées. Opacité d'origine : guide 90 %, options 95 %, ciblage 85 %.",
      en = "Map buttons grouped in a single bar: same size for all (smaller on the reduced map), boxes shown properly. Original opacity: guide 90%, options 95%, targeting 85%." },
    { v = "1.25", fr = "Fond des fenêtres (guide, options, ciblage) à 95 % d'opacité.",
      en = "Window backgrounds (guide, options, targeting) at 95% opacity." },
    { v = "1.24", fr = "Cases cochées bien visibles (losange rouge plein). Boutons de la carte du monde plus petits quand la carte est réduite.",
      en = "Checked boxes clearly visible (solid red diamond). World map buttons smaller when the map is not maximized." },
    { v = "1.23", fr = "Clic droit sur < ou > : revient exactement à l'étape actuelle (il avançait ou reculait aussi d'une étape).",
      en = "Right-click on < or >: goes back exactly to the current step (it also moved one step forward or back)." },
    { v = "1.22", fr = "Icônes de l'addon aussi dans la fenêtre de ciblage (donneur, à qui rendre, monstre), dans les listes « Rends ici » / « Prends ici », dans la légende des options et dans le conseil « journal plein ».",
      en = "Addon icons also in the targeting window (giver, turn in to, mob), in the \"Turn in here\" / \"Pick up here\" lists, in the options legend and in the \"quest log full\" tip." },
    { v = "1.21", fr = "Icônes de « La suite » et flèche de destination remises à l'endroit.",
      en = "\"Coming up\" icons and destination arrow shown the right way up." },
    { v = "1.20", fr = "Icônes de l'addon dans « La suite » (flèche retour pour rendre, point d'exclamation doré pour prendre, épées pour faire) et flèche de destination redessinée, à la place des icônes du jeu.",
      en = "Addon icons in \"Coming up\" (return arrow to turn in, gold exclamation mark to accept, swords to do) and a redrawn destination arrow, instead of the game's icons." },
    { v = "1.19", fr = "Fenêtre aux proportions de la maquette : largeur 300, hauteur fixe (elle ne grandit que si le contenu dépasse), boutons et pied ancrés en bas, pied toujours visible. Objectifs en lignes avec le compteur aligné à droite. Boutons transparents à contour doré, niveau en crème.",
      en = "Window with the mockup's proportions: 300 wide, fixed height (it only grows if the content needs it), buttons and footer pinned to the bottom, footer always visible. Objectives as rows with the counter aligned right. Transparent gold-outlined buttons, cream level number." },
    { v = "1.18", fr = "Fenêtre : texte un peu plus petit en gardant les espacements, plus d'espace avant les boutons, fond plus opaque (le décor ne teinte plus la fenêtre) et couleurs alignées sur la maquette.",
      en = "Window: slightly smaller text with the same spacing, more room above the buttons, more opaque background (the scenery no longer tints the window) and colors matched to the mockup." },
    { v = "1.17", fr = "Fenêtre plus grande et plus aérée (texte plus gros, plus d'espace). Prendre / Rendre : le PNJ est dans le bloc destination. Astuces dans l'infobulle du titre. Cases oui/non en losange à contour doré (le losange plein reste pour les choix uniques), partout : options, carte, objectifs. Quêtes de métier en double retirées de l'onglet Métiers.",
      en = "Bigger, airier window (larger text, more spacing). Accept / Turn in: the NPC is in the destination block. Tips in the title tooltip. Yes/no boxes are now gold-outlined diamonds (the solid diamond stays for single choices), everywhere: options, map, objectives. Duplicate profession quests removed from the Professions tab." },
    { v = "1.16", fr = "Nouveau look : en-tête avec la zone et une barre de progression, badge du niveau de la quête, bloc destination (lieu, précision, distance), objectifs en cases à cocher, liste « La suite » avec icônes et distances (les étapes passées sont regroupées). Options et boutons de la carte (Trophées de guerre, entraîneurs) aux mêmes couleurs.",
      en = "New look: header with the zone and a progress bar, quest level badge, destination block (place, details, distance), objectives as checkboxes, \"Coming up\" list with icons and distances (passed steps are grouped). Options and map buttons (War Trophies, trainers) in the same colors." },
    { v = "1.15", fr = "Fenêtre du guide plus lisible : les indications sont présentées en listes (Ensuite, Rends ici, Prends ici, En chemin, Plus tard…). Clic sur le titre de la quête : elle s'ouvre dans le journal des quêtes.",
      en = "Easier-to-read guide window: hints are shown as lists (Next, Turn in here, Pick up here, On the way, Later...). Click the quest title to open it in the quest log." },
    { v = "1.14", fr = "Étapes « Faire » : la fenêtre affiche les objectifs de la quête en direct, groupés par action (Tue, Ramasse, Utilise…), avec un crochet vert quand c'est fini. Le texte complet de l'étape est dans l'infobulle du titre.",
      en = "\"Do\" steps: the window shows the quest objectives live, grouped by action (Kill, Collect, Use...), with a green check when done. The full step text is in the title tooltip." },
    { v = "1.13", fr = "Cibles de l'objectif : sur un jeu dans une autre langue que l'anglais, les noms des monstres sont appris en les voyant (clic pour cibler et grisé corrects). Flèche réaffichée au changement d'étape. Le rappel de sorts n'est plus effacé par un entraîneur de métier. Bouton d'objet de quête affiché même si le jeu ne donne pas le sort de l'objet. Deux nouvelles cases : « Aller au PNJ le plus proche » et « Flèche intelligente » (onglet Automatismes).",
      en = "Objective targets: on a non-English game, mob names are learned when you see them (target click and greying work). Arrow shown again when the step changes. The spell reminder is no longer cleared by a profession trainer. Quest item button shown even if the game doesn't give the item's spell. Two new options: \"Go to the closest NPC\" and \"Smart arrow\" (Automation tab)." },
    { v = "1.12", fr = "Flèche : cachée dès que tu es dans la zone de chasse (revient au-delà de 250 m), vers ton corps quand tu es mort, et l'entrée d'une grotte sert à toutes ses étapes. Cibles : chaque objectif a sa place (8 lignes) et les monstres pas en vue sont grisés. Une remise faisable à côté de toi passe en premier, même loin dans le guide. Bouton d'objet de quête jamais hors de l'écran. Onglet Donjons plus compact.",
      en = "Arrow: hidden as soon as you are in the hunting area (back beyond 250 m), points to your corpse when dead, and a cave entrance serves all its steps. Targets: each objective gets a slot (8 rows) and mobs not in view are greyed out. A turn-in you can do right next to you comes first, even far ahead in the guide. Quest item button never off-screen. More compact Dungeons tab." },
    { v = "1.11", fr = "Spécialisation : sur Forever, les 3 arbres de talents sont lus séparément (par colonne) pour trouver celui où tu as mis le plus de points.",
      en = "Specialization: on Forever, the 3 talent trees are read separately (by column) to find the one where you spent the most points." },
    { v = "1.10", fr = "Spécialisation : essai par les talents modernes (C_SpecializationInfo et arbres de traits). /warpath diag détaille ce qu'ils renvoient.",
      en = "Specialization: also tried through modern talents (C_SpecializationInfo and trait trees). /warpath diag details what they return." },
    { v = "1.09", fr = "Spécialisation : lecture des arbres de talents au format récent. /warpath diag liste les fonctions de talents fournies par le jeu.",
      en = "Specialization: talent trees are also read in the newer format. /warpath diag lists the talent functions the game provides." },
    { v = "1.08", fr = "En allant vers un PNJ, le guide te rappelle de ramasser en chemin les objets de quête qui traînent le long du trajet (ex. Cactus Apples). La flèche vers les objets au sol est réservée à ceux qui sont toujours au même endroit.",
      en = "On the way to an NPC, the guide reminds you to pick up quest objects lying along the route (e.g. Cactus Apples). The arrow to ground objects is kept for objects that are always in the same place." },
    { v = "1.07", fr = "À chaque niveau pair, si ton entraîneur de classe est à moins de 250 m, le guide ajoute une étape pour aller apprendre tes nouveaux sorts (OK pour la passer).",
      en = "At each even level, if your class trainer is within 250 m, the guide adds a step to go learn your new spells (OK to skip it)." },
    { v = "1.06", fr = "Le taux de drop n'est plus répété dans la fenêtre du guide : il est affiché à côté des monstres dans « Cibles de l'objectif » (sauf si tu as masqué cette fenêtre).",
      en = "The drop rate is no longer repeated in the guide window: it is shown next to the mobs in \"Objective targets\" (unless you hid that window)." },
    { v = "1.05", fr = "Grottes : l'entrée est apprise dès que tu entres dans une grotte du guide, même si tu n'es pas encore à cette étape.",
      en = "Caves: the entrance is learned as soon as you enter a cave from the guide, even if you are not at that step yet." },
    { v = "1.04", fr = "En regardant d'autres étapes, une ligne « Revenir à l'étape actuelle » te ramène à ton étape (aussi : clic droit sur < ou >, ou un raccourci clavier). Le temps par monstre est mesuré selon ta spécialisation. Nouvelle commande /warpath diag pour vérifier ce que le jeu fournit à l'addon.",
      en = "While looking at other steps, a \"Back to the current step\" line brings you back (also: right-click < or >, or a key binding). Time per mob is measured per specialization. New /warpath diag command to check what the game gives the addon." },
    { v = "1.03", fr = "Les PNJ des villages sont situés par rapport à l'auberge (« 140 m à l'est de l'auberge »). Les entrées de grottes apprises par les autres joueurs sont intégrées. La Chronique ne note plus un niveau ou un argent faux à la déconnexion.",
      en = "Village NPCs are located relative to the inn (\"140 m east of the inn\"). Cave entrances learned by other players are included. The Chronicle no longer records a wrong level or gold at logout." },
    { v = "1.02", fr = "Moins d'allers-retours : le guide va au PNJ le plus proche et te fait prendre ou rendre les quêtes en passant. Cibles de l'objectif avec icônes et taux de drop, cibles finies retirées. Flèche vers les objets au sol et l'entrée des grottes. Entraîneurs de classe et maîtres d'armes sur la carte, métiers demandés dès le début. Fenêtre pour décrire un problème.",
      en = "Fewer back-and-forth trips: the guide goes to the closest NPC and has you pick up or turn in quests on the way. Objective targets with icons and drop rates, finished targets removed. Arrow to ground objects and cave entrances. Class trainers and weapon masters on the map, professions asked from the start. A window to describe a problem." },
    { v = "1.01", fr = "Donjons : le journal se ferme tout seul quand tu sors (vivant, quêtes faites ou groupe dissous), « Revenir au journal » si tu l'as quitté par erreur, et proposition de basculer si tu entres dans un autre donjon. La Chronique compte le donjon dès l'entrée et ignore les morts en champ de bataille.",
      en = "Dungeons: the log closes by itself when you leave (alive, quests done or group disbanded), \"Back to the log\" if you left it by mistake, and an offer to switch if you enter another dungeon. The Chronicle counts the dungeon on entry and ignores battleground deaths." },
    { v = "1.00", fr = "Version 1.0 ! Le journal du donjon ne s'ouvre que dans le bon donjon, le changement de zone est reproposé une fois 3 niveaux plus tard, et cette fenêtre résume les nouveautés au lieu de toutes les lister.",
      en = "Version 1.0! The dungeon log only opens in the right dungeon, the zone change is offered again once 3 levels later, and this window sums up the updates instead of listing them all." },
    { v = "0.99", fr = "Petites corrections : à l'entrée d'un donjon, la liste « Ensuite » montre les remises au lieu des objectifs du donjon ; le comptage des drops reconnaît le nom des objets dans la langue du jeu.",
      en = "Small fixes: at a dungeon entrance, the \"Next\" list shows the turn-ins instead of the dungeon objectives; drop counting recognizes item names in the game's language." },
    { v = "0.98", fr = "Chaque donjon a maintenant son propre texte d'ambiance à l'entrée : son histoire, pourquoi la Horde t'y envoie, et ton nom de héros.",
      en = "Each dungeon now has its own flavor text at the entrance: its story, why the Horde sends you there, and your hero's name." },
    { v = "0.96", fr = "Donjons : l'entrée ne se coche plus toute seule quand une quête du donjon a été passée. Après « Sortie du donjon », le guide t'envoie seulement rendre les quêtes complétées ; revenir dans l'instance rouvre le journal.",
      en = "Dungeons: the entrance no longer checks itself when a dungeon quest was skipped. After \"Leave the dungeon\", the guide only sends you to turn in completed quests; going back into the instance reopens the log." },
    { v = "0.95", fr = "Donjons : l'étape d'entrée reste affichée (avec le message de rassemblement) jusqu'à ce que tu entres vraiment dans l'instance. Le journal du donjon apparaît seulement une fois à l'intérieur.",
      en = "Dungeons: the entrance step stays on screen (with the rally message) until you actually enter the instance. The dungeon quest log only shows up once inside." },
    { v = "0.94", fr = "En regardant les étapes avec < >, l'en-tête indique maintenant (faite), (passée) ou (à faire) au lieu de (aperçu).",
      en = "When browsing steps with < >, the header now shows (done), (skipped) or (to do) instead of (preview)." },
    { v = "0.93", fr = "Mode donjon : une fois tes quêtes en main, le guide te dit de rassembler ton groupe. À l'entrée, la fenêtre devient le journal du donjon (progression de chaque quête, détails au clic) ; « Sortie du donjon » te ramène aux remises. Une étape passée par erreur se rétablit d'un clic (bouton RÉTABLIR ou clic sur l'en-tête). « Cibles de l'étape » devient « Cibles de l'objectif ».",
      en = "Dungeon mode: once your quests are in hand, the guide tells you to gather your group. At the entrance, the window becomes the dungeon quest log (progress for each quest, details on click); \"Leave the dungeon\" takes you back to turn-ins. A step skipped by mistake is restored in one click (RESTORE button or click on the header). \"Step targets\" becomes \"Objective targets\"." },
    { v = "0.92", fr = "Donjons : les objectifs à faire dans la zone du donjon (même avant le portail) rappellent maintenant de les faire avec ton groupe, car les monstres y sont souvent élites.",
      en = "Dungeons: objectives in the dungeon area (even before the portal) now remind you to do them with your group, since the mobs there are often elite." },
    { v = "0.91", fr = "La Chronique de guerre s'affiche maintenant par-dessus les options au lieu de se mélanger avec elles.",
      en = "The War Chronicle now shows on top of the options instead of blending into them." },
    { v = "0.90", fr = "Taux de drop corrigé : les objets obtenus n'étaient jamais comptés sur Forever (seulement les monstres fouillés), ce qui faisait baisser le pourcentage. Ils sont maintenant comptés par la progression de la quête. Les anciennes mesures faussées ont été effacées.",
      en = "Drop rates fixed: items obtained were never counted on Forever (only looted mobs), which kept lowering the percentage. They are now counted through quest progress. The old skewed measurements were cleared." },
    { v = "0.89", fr = "Nouveau : la Chronique de guerre. À la connexion, une bannière résume ta dernière séance (temps actif, XP, quêtes, donjons, trophées) avec une note de S à D et des mentions. Elle ne revient pas au /reload. Bouton dans les options (onglet Automatisation) ou /warpath chronique.",
      en = "New: the War Chronicle. At login, a banner sums up your last session (active time, XP, quests, dungeons, trophies) with a grade from S to D and honors. It does not come back on /reload. Button in the options (Automation tab) or /warpath chronicle." },
    { v = "0.88", fr = "Les étapes « Va à » (entrée d'un donjon, point de passage) se valident toutes seules quand tu arrives sur place : plus besoin de cliquer OK.",
      en = "\"Go to\" steps (dungeon entrance, waypoint) now complete on their own when you arrive: no need to click OK anymore." },
    { v = "0.87", fr = "Ramassage des quêtes de donjon : Blackrock Depths, Razorfen Downs et The Excavation ont maintenant un vrai trajet le plus court (une quête prise dans le donjon bloquait le calcul). Les très longues listes de quêtes ont aussi un ordre optimisé.",
      en = "Dungeon quest pickup: Blackrock Depths, Razorfen Downs and The Excavation now get a real shortest route (a quest picked up inside the dungeon blocked the calculation). Very long quest lists also get an optimized order." },
    { v = "0.86", fr = "Ramassage des quêtes de donjon : une quête bloquée par un prérequis encore dans ton journal (ex. Altered Beings avant Hamuul Runetotem) est maintenant intégrée au trajet le plus court, au lieu d'être repoussée à la fin.",
      en = "Dungeon quest pickup: a quest blocked by a prerequisite still in your log (e.g. Altered Beings before Hamuul Runetotem) is now part of the shortest route instead of being pushed to the end." },
    { v = "0.85", fr = "La fenêtre du guide affiche maintenant le taux de drop des objets que tu cherches. Il part de la base Questie, puis s'ajuste avec les monstres que tu fouilles (et ceux de ton groupe ou ta guilde).",
      en = "The guide window now shows the drop rate of the items you are looking for. It starts from the Questie base, then adjusts with the mobs you loot (and those of your party or guild)." },
    { v = "0.84", fr = "Zones de chasse et de ramassage : la flèche se cache quand tu y es (moins de 50 m) et revient si tu t'éloignes.",
      en = "Hunting and gathering areas: the arrow hides once you are there (under 50 m) and comes back if you wander off." },
    { v = "0.83", fr = "Quand tu atteins le niveau de fin d'une zone, le guide te propose de passer à la suivante. Il liste les quêtes à finir avant de partir et celles qui continuent dans la prochaine zone.",
      en = "When you reach a zone's end level, the guide offers to move on to the next one. It lists the quests worth finishing before leaving and those that continue in the next zone." },
    { v = "0.82", fr = "Plus de quêtes qui restent coincées dans ton journal : la livraison pour Apothecary Zamah se rend maintenant en préparant Wailing Caverns, et cinq quêtes que le guide ne faisait jamais terminer ont été retirées. « TROP BAS » apparaît dès que le guide passe à la zone suivante.",
      en = "No more quests stuck in your log: the delivery for Apothecary Zamah is now turned in while preparing Wailing Caverns, and five quests the guide never had you finish were removed. \"TOO LOW\" shows as soon as the guide moves on to the next zone." },
    { v = "0.81", fr = "Trophées de guerre : les champs de bataille et arènes ne comptent plus (seulement le PvP en monde ouvert), et la liste garde les 300 plus récents. Les messages d'erreur suivent la langue choisie.",
      en = "War Trophies: battlegrounds and arenas no longer count (open-world PvP only), and the list keeps the 300 most recent. Error messages now follow the chosen language." },
    { v = "0.80", fr = "Les zones trop basses pour ton niveau, mais jamais faites, affichent maintenant « TROP BAS » au lieu de « ACHEVÉ ». « ACHEVÉ » apparaît seulement si tu as vraiment rendu les quêtes de la zone.",
      en = "Zones too low for your level that you never did now show \"TOO LOW\" instead of \"COMPLETE\". \"COMPLETE\" only shows when you actually turned in the zone's quests." },
    { v = "0.79", fr = "« Sentier de la guerre » devient « Trophées de guerre ». Les boutons de la carte suivent maintenant la langue choisie dans les options.",
                  en = "\"Warpath kills\" is now \"War Trophies\". The map buttons now follow the language chosen in the options." },
    { v = "0.78", fr = "Le dossier de l'addon est rangé en sous-dossiers (Core, Data, Features, Locale, Media, UI). Rien ne change en jeu.",
                  en = "The addon folder is now organized in subfolders (Core, Data, Features, Locale, Media, UI). Nothing changes in game." },
    { v = "0.77", fr = "Bouton « Signaler un problème » en bas à gauche des options (même chose que /warpath bug, avec une note facultative).",
                  en = "\"Report a problem\" button at the bottom left of the options (same as /warpath bug, with an optional note)." },
    { v = "0.76", fr = "Les noms des métiers suivent la langue de ton jeu. Les entraîneurs de tes métiers sont sur la carte du monde (bouton « Entraîneurs de métier », clic = point de passage). Conseil corrigé : un seul suivi de récolte sur la minicarte à la fois.",
                  en = "Profession names follow your game's language. Your professions' trainers are on the world map (\"Profession trainers\" button, click = waypoint). Tip fixed: only one gathering tracking on the minimap at a time." },
    { v = "0.75", fr = "La première fois que tu te reposes dans un camp ou une ville (niveau 5+), l'addon te demande quels métiers tu comptes prendre et ouvre l'onglet Métiers.",
                  en = "The first time you rest in a camp or a city (level 5+), the addon asks which professions you plan to take and opens the Professions tab." },
    { v = "0.74", fr = "Métiers : un nouvel onglet dans les options pour cocher tes métiers (détectés automatiquement). Leurs quêtes te sont proposées quand tu passes dans leur zone, et la liste complète est dans l'onglet.",
                  en = "Professions: a new options tab to check your professions (detected automatically). Their quests are offered when you pass through their zone, and the full list is in the tab." },
    { v = "0.73", fr = "Ailes de donjon vérifiées : The Darkstone Tablet et Tinkee Steamboil passent dans Upper Blackrock Spire ; les quêtes réservées aux forgerons sont retirées des guides de donjon.",
                  en = "Dungeon wings checked: The Darkstone Tablet and Tinkee Steamboil move to Upper Blackrock Spire; blacksmith-only quests are removed from the dungeon guides." },
    { v = "0.72", fr = "Donjons : la proposition dit combien de quêtes tu peux prendre maintenant et à quel niveau tu pourras toutes les prendre (« Plus tard » te la repropose à ce niveau). Scarlet Monastery, Maraudon, Dire Maul, Blackrock Spire et Stratholme sont séparés par aile, avec leurs propres niveaux et quêtes.",
                  en = "Dungeons: the offer tells you how many quests you can take now and at which level you can take them all (\"Later\" asks again at that level). Scarlet Monastery, Maraudon, Dire Maul, Blackrock Spire and Stratholme are split by wing, with their own levels and quests." },
    { v = "0.71", fr = "Audit des guides 35-60 : paliers de niveau quand une quête exige un niveau précis (plus d'étape bloquée), deux ordres de quêtes corrigés (Riverglades, Western Plaguelands), Un'Goro en deux boucles, sept quêtes ajoutées.",
                  en = "Audit of the 35-60 guides: level gates when a quest needs a specific level (no more stuck step), two quest orders fixed (Riverglades, Western Plaguelands), Un'Goro in two loops, seven quests added." },
    { v = "0.70", fr = "Paladins réprouvés : la quête de monture du niveau 40 (A Paladin's Steed) est proposée.",
                  en = "Forsaken paladins: the level-40 mount quest (A Paladin's Steed) is now offered." },
    { v = "0.69", fr = "Ta progression ne se décale plus quand le guide est mis à jour. Nouvelles options : Sentier de la guerre, capture d'écran, XP/h actif au bas de la fenêtre. Cette fenêtre « Quoi de neuf ».",
                  en = "Your progress no longer shifts when the guide is updated. New options: Warpath kills, screenshot, active XP/h at the bottom of the window. This \"What's new\" window." },
    { v = "0.68", fr = "Fenêtres de question, bulles d'info, boutons de ciblage et messages du chat aux couleurs de l'addon.",
                  en = "Question windows, tooltips, target buttons and chat messages in the addon's colours." },
    { v = "0.66", fr = "Sentier de la guerre : X rouges sur la carte là où tu as tué l'Alliance (/warpath pvp).",
                  en = "Warpath kills: red X on the map where you killed the Alliance (/warpath pvp)." },
    { v = "0.65", fr = "Temps de jeu actif et XP/h, sans l'AFK ni les métiers (/warpath temps).",
                  en = "Active play time and XP/h, without AFK or professions (/warpath time)." },
    { v = "0.62", fr = "Avertissements PvP au début des zones contestées.", en = "PvP warnings at the start of contested zones." },
    { v = "0.61", fr = "Nouveau guide : le mont Hyjal (55-60).", en = "New guide: Mount Hyjal (55-60)." },
}
local function vnum(v) local a, b = tostring(v or "0"):match("^(%d+)%.(%d+)"); return (tonumber(a) or 0) * 1000 + (tonumber(b) or 0) end

function ShowNews(all)
    local seen = vnum(WarpathDropDB and WarpathDropDB._seenVer or "0")
    local lines, n, more = {}, 0, 0
    local cap = all and 6 or 3
    for _, e in ipairs(NEWS) do
        if all or vnum(e.v) > seen then
            if n < cap then
                n = n + 1
                lines[#lines + 1] = "|cffd6b866" .. e.v .. "|r  " .. ((Lang and Lang() == "en") and e.en or e.fr)
            else more = more + 1 end
        end
    end
    if WarpathDropDB then WarpathDropDB._seenVer = VERSION end
    if n == 0 then return false end
    if more > 0 and not all then lines[#lines + 1] = "|cff8c7f62" .. T("newsMore", more) .. "|r" end
    StaticPopupDialogs["WARPATH_NEWS"] = { text = "%s", button1 = T("newsOk"), timeout = 0, whileDead = true, hideOnEscape = true }
    -- v1.41 (audit) : apres une mise a jour, un bandeau discret (10 s) plutot qu'une fenetre ; clic = le detail.
    -- /warpath news ouvre toujours la fenetre complete.
    if not all and Toast then
        local txt = T("newsHead", VERSION) .. "\n\n" .. table.concat(lines, "\n\n")
        Toast(T("popNews"), T("newsToast", VERSION), function() Popup("WARPATH_NEWS", txt) end)
        return true
    end
    Popup("WARPATH_NEWS", T("newsHead", VERSION) .. "\n\n" .. table.concat(lines, "\n\n"))
    return true
end

function ShowWelcome()
    if DB and DB.welcomed then
        if WarpathDropDB and WarpathDropDB._seenVer == nil then WarpathDropDB._seenVer = "0.68" end -- deja installe avant le Quoi de neuf
        if WarpathDropDB and vnum(WarpathDropDB._seenVer) < vnum(VERSION) then ShowNews(false) end
        return
    end
    if not DB or DB.welcomed or not StaticPopup_Show then return end
    -- v1.43 : bienvenue en 2 temps. 1) visite ou non ; 2) options / c'est parti (texte complet sans visite,
    -- version courte apres la visite). Le choix du 1er temps suffit a ne plus redemander la bienvenue.
    local function welcomed()
        DB.welcomed = true
        if WarpathDropDB then WarpathDropDB._seenVer = VERSION end
    end
    local function last(key)
        return {
            text = key, button1 = T("welcomeOpts"), button2 = T("welcomeGo"),
            OnAccept = function() SlashCmdList.WARPATH("options") end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
    end
    StaticPopupDialogs["WARPATH_WELCOME"] = last(T("welcome", WarpathName()))
    StaticPopupDialogs["WARPATH_WELCOME_DONE"] = last(T("tutoDone"))
    StaticPopupDialogs["WARPATH_WELCOME_ASK"] = {
        text = T("welcomeAsk", WarpathName()), button1 = T("welcomeTour"), button2 = T("welcomeNoTour"),
        OnAccept = function()
            welcomed()
            ShowTutorial(true, function() Popup("WARPATH_WELCOME_DONE") end)
        end,
        OnCancel = function(_, _, reason)
            welcomed(); DB.tutoSeen = true
            if reason == "clicked" then Popup("WARPATH_WELCOME") end   -- Echap = on ferme tout
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    ns.Trace("popup WARPATH_WELCOME_ASK"); Popup("WARPATH_WELCOME_ASK")
end

-- Fenetre de signalement : decris ce qui s'est passe, puis Envoyer (= /warpath bug <texte>)
do
    local win
    function BugWindow()
        if not win then
            win = CreateFrame("Frame", "WarpathBugWindow", UIParent)
            win:SetSize(380, 250); win:SetPoint("CENTER", 0, 60)
            win:SetFrameStrata("FULLSCREEN_DIALOG"); win:EnableMouse(true); win:SetClampedToScreen(true)
            win:SetMovable(true); win:RegisterForDrag("LeftButton")
            win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
            local bg = Tex(win, COL.bg, 0.97, "BACKGROUND"); bg:SetAllPoints()
            for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
                local t = Tex(win, COL.line)
                if side == "TOP" or side == "BOTTOM" then t:SetHeight(1); t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
                else t:SetWidth(1); t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side) end
            end
            -- v1.41 (uniformisation) : en-tete standard (34 px, losange rouge, titre a gauche, « x »)
            win:SetHeight(264)
            local hbg = Tex(win, COL.panel or COL.bg, 1, "BORDER"); hbg:SetHeight(34); hbg:SetPoint("TOPLEFT", 1, -1); hbg:SetPoint("TOPRIGHT", -1, -1)
            local hln = Tex(win, COL.line, 1, "ARTWORK"); hln:SetHeight(1); hln:SetPoint("TOPLEFT", 0, -34); hln:SetPoint("TOPRIGHT", 0, -34)
            local gem = Diamond(win, 8, COL.red); gem:SetPoint("LEFT", win, "TOPLEFT", 14, -17)
            win.head = FS(win, 12, COL.white, FONT, "LEFT"); win.head:SetPoint("LEFT", win, "TOPLEFT", 30, -17)
            local x = HeadButton(win, "x"); x:SetPoint("RIGHT", win, "TOPRIGHT", -6, -17)
            x:SetScript("OnClick", function() win:Hide() end)
            win.sub = FS(win, 11, COL.soft, FONT, "LEFT"); win.sub:SetPoint("TOPLEFT", 16, -46); win.sub:SetWidth(348)
            local box = CreateFrame("EditBox", nil, win)
            box:SetPoint("TOPLEFT", 16, -84); box:SetPoint("BOTTOMRIGHT", -16, 46)
            box:SetMultiLine(true); box:SetAutoFocus(true); box:SetMaxLetters(600)
            if box.SetFontObject then box:SetFontObject(ChatFontNormal) end
            if box.SetFont then pcall(box.SetFont, box, FONT, 12, "") end
            if box.SetTextInsets then box:SetTextInsets(6, 6, 6, 6) end
            local bbg = Tex(box, COL.faint, 0.35, "BACKGROUND"); bbg:SetAllPoints()
            box:SetScript("OnEscapePressed", function() win:Hide() end)
            win.box = box
            win.send = FlatButton(win, 110, 22, function()
                local t = (win.box:GetText() or ""):gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
                SlashCmdList.WARPATH("bug " .. (t ~= "" and t or "-"))
                win:Hide()
            end)
            win.send:SetPoint("BOTTOMRIGHT", -16, 14)
            win.cancel = FlatButton(win, 90, 22, function() win:Hide() end)
            win.cancel:SetPoint("RIGHT", win.send, "LEFT", -8, 0)
            if UISpecialFrames then table.insert(UISpecialFrames, "WarpathBugWindow") end
        end
        win.head:SetText(Caps(T("bugTitle")))
        win.sub:SetText(T("bugExplain"))
        win.send:SetLabel(Caps(T("bugSend"))); win.cancel:SetLabel(Caps(T("chClose")))
        win.box:SetText("")
        win:Show(); if win.Raise then win:Raise() end
        if win.box.SetFocus then win.box:SetFocus() end
    end
end
