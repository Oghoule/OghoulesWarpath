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
        f:SetShown(not f:IsShown())
        DB.shown = f:IsShown()
        if ns.Targets then ns.Targets.Refresh() end
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
    elseif cmd == "diag" then
        -- ce que le jeu fournit a l'addon (pour verifier ce qui marche sur Forever)
        local function yn(v) return v and "|cff9cc7a8OK|r" or "|cffc24a3eNON|r" end
        local okS, sp = pcall(function() return GetSpecialization and GetSpecialization() end)
        local okT, tab = pcall(function() return GetTalentTabInfo and select(3, GetTalentTabInfo(1)) end)
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
        say(T("diagData", nC, nB, wm, (GetLocale and GetLocale()) or "?", Lang()))
    elseif cmd == "classe" or cmd == "class" then
        local list = ClassQuestList()
        local n = tonumber(arg)
        if n and list[n] and list[n].q and not list[n].done then AskChain(list[n].q, true); return end
        if #list == 0 then say(T("classNone")); return end
        for k, c in ipairs(list) do
            say(string.format("  %d. %s%s (%d)|r%s", k, c.done and "|cff8c7f62" or "|cffcdbb8e", c.name, c.lvl, c.done and (" - " .. T("classDone")) or ""))
        end
    elseif cmd == "news" or cmd == "nouveautes" or cmd == "quoi" then
        if not ShowNews(true) then say(T("newsNone")) end
    elseif cmd == "chronique" or cmd == "chronicle" or cmd == "chron" then
        ChronShow(arg == "now" and 0 or nil)
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
_G.BINDING_HEADER_WARPATH = "Oghoule's Warpath"
_G.BINDING_NAME_WARPATH_OK = "Valider / passer l'étape"
_G.BINDING_NAME_WARPATH_PREV = "Voir l'étape précédente"
_G.BINDING_NAME_WARPATH_NEXT = "Voir l'étape suivante"
_G.BINDING_NAME_WARPATH_TOGGLE = "Afficher / cacher le guide"
_G.BINDING_NAME_WARPATH_OPTIONS = "Ouvrir les options"
_G.BINDING_NAME_WARPATH_NOW = "Revenir à l'étape actuelle"
_G["BINDING_NAME_CLICK WarpathTarget1:LeftButton"] = "Cibler la 1re cible de l'étape"
_G["BINDING_NAME_CLICK WarpathTarget2:LeftButton"] = "Cibler la 2e cible de l'étape"
_G.WarpathBinding = function(action)
    if action == "ok" then Ignore()
    elseif action == "prev" then Peek(-1)
    elseif action == "next" then Peek(1)
    elseif action == "now" then BackToNow()
    elseif action == "toggle" then SlashCmdList.WARPATH("toggle")
    elseif action == "options" then SlashCmdList.WARPATH("options") end
end

-- Premier lancement : courte presentation
-- Quoi de neuf : les nouveautes depuis la derniere version que tu as vue (une fois par compte)
local NEWS = {
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
    StaticPopupDialogs["WARPATH_WELCOME"] = {
        text = T("welcome", WarpathName()), button1 = T("welcomeOpts"), button2 = T("welcomeGo"),
        OnAccept = function() DB.welcomed = true; if WarpathDropDB then WarpathDropDB._seenVer = VERSION end; SlashCmdList.WARPATH("options") end,
        OnCancel = function() DB.welcomed = true; if WarpathDropDB then WarpathDropDB._seenVer = VERSION end end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    ns.Trace("popup WARPATH_WELCOME"); Popup("WARPATH_WELCOME")
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
            win.head = FS(win, 10, COL.gold, FONT, "CENTER"); win.head:SetPoint("TOP", 0, -12)
            win.sub = FS(win, 11, COL.soft, FONT, "LEFT"); win.sub:SetPoint("TOPLEFT", 16, -32); win.sub:SetWidth(348)
            local box = CreateFrame("EditBox", nil, win)
            box:SetPoint("TOPLEFT", 16, -70); box:SetPoint("BOTTOMRIGHT", -16, 46)
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
