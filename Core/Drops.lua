-- Oghoule's Warpath : taux de drop des objets de quete
-- 1. Mesure : monstres tues qui peuvent donner un objet cherche, objets arrives dans les sacs.
-- 2. Partage : echange anonyme des compteurs avec les joueurs de l'addon (groupe, guilde).
-- 3. Donnees integrees : ns.BakedDrops (DropsData.lua), fusion des sauvegardes envoyees par les joueurs.
local _, ns = ...
local Drops = {}
ns.Drops = Drops

-- Mesure des drops : on compte les monstres tues qui peuvent donner un objet de quete que tu cherches,
-- et les objets qui arrivent dans tes sacs. Partage entre tous tes personnages (WarpathDropDB).
local dropTrack, dropCount, dropQuest, dropName = {}, {}, {}, {}   -- objet -> pnj ; nombre ; quete ; nom
-- nombre d'objets obtenus : sacs (C_Item, l'ancienne fonction n'existe plus sur Forever) ou, mieux, la
-- progression de l'objectif de quete (compte aussi les objets de quete qui ne vont pas dans les sacs)
local function Count(item)
    local n = 0
    if C_Item and C_Item.GetItemCount then n = C_Item.GetItemCount(item) or 0
    elseif GetItemCount then n = GetItemCount(item) or 0 end
    local q, name = dropQuest[item], dropName[item]
    -- nom de l'objet dans la langue du jeu (les donnees sont en anglais : un client francais ne le trouverait pas)
    local loc = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(item)
    if type(loc) == "string" and loc ~= "" then name = loc end
    if q and C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objs = pcall(C_QuestLog.GetQuestObjectives, q)
        if ok and type(objs) == "table" then
            for _, o in ipairs(objs) do
                if o.type == "item" and type(o.text) == "string" and (#objs == 1 or (name and o.text:find(name, 1, true))) then
                    n = math.max(n, o.numFulfilled or 0)
                end
            end
        end
    end
    return n
end
Drops.Count = Count
function Drops.Refresh(logById, EST)
    pcall(Drops.OnBagUpdate)            -- compte d'abord ce qui vient d'arriver (avant qu'une quete complete sorte du suivi)
    -- une fois : on oublie les anciennes mesures faussees (objets jamais comptes avant la v0.90)
    if WarpathDropDB and not WarpathDropDB._v90 then
        for item, st in pairs(WarpathDropDB) do
            if type(item) == "number" and type(st) == "table" and (st.n or 0) == 0 then WarpathDropDB[item] = nil end
        end
        WarpathDropDB._from = nil
        WarpathDropDB._v90 = true
    end
    wipe(dropTrack)
    for q, complete in pairs(logById) do
        local e = EST[q]
        if e and e.d and not complete then
            for _, d in ipairs(e.d) do
                if #d >= 7 and d[5] ~= 1 then
                    local set = {}
                    for j = 7, #d do set[d[j]] = true end
                    dropTrack[d[1]] = set
                    dropQuest[d[1]], dropName[d[1]] = q, d[6]
                    if dropCount[d[1]] == nil then dropCount[d[1]] = Count(d[1]) end
                end
            end
        end
    end
end

function Drops.OnPartyKill(destGUID)
    local kind, _, _, _, _, id = strsplit("-", destGUID or "")
    id = tonumber(id)
    if not id or (kind ~= "Creature" and kind ~= "Vehicle") then return end
    for item, set in pairs(dropTrack) do
        if set[id] then
            WarpathDropDB[item] = WarpathDropDB[item] or { k = 0, n = 0 }
            WarpathDropDB[item].k = WarpathDropDB[item].k + 1
        end
    end
end

-- Chaque corps fouille compte une fois (meme fouille en plusieurs fois) : c'est le "nombre de monstres"
-- des taux de drop. Plus juste que les kills : un monstre non fouille ne fausse rien.
local looted, lootedN = {}, 0
function Drops.OnLootOpened()
    if not GetNumLootItems or not GetLootSourceInfo then return end
    for slot = 1, GetNumLootItems() do
        local src = { GetLootSourceInfo(slot) }
        for k = 1, #src, 2 do
            local guid = src[k]
            if type(guid) == "string" and not looted[guid] then
                looted[guid] = true; lootedN = lootedN + 1
                if lootedN > 500 then wipe(looted); lootedN = 0 end
                Drops.OnPartyKill(guid)
            end
        end
    end
end

function Drops.OnBagUpdate()
    for item in pairs(dropTrack) do
        local now = Count(item)
        local before = dropCount[item] or now
        if now > before and WarpathDropDB[item] then
            local st = WarpathDropDB[item]
            st.n = math.min(st.k, st.n + (now - before))   -- jamais plus d'objets que de monstres comptes
        end
        dropCount[item] = now
    end
end

function Drops.Tracking() return next(dropTrack) ~= nil end

------------------------------------------------------------------
-- Partage des taux de drop entre joueurs de l'addon (messages d'addon invisibles, groupe et guilde).
-- On n'envoie que SES propres compteurs ; pour chaque joueur on garde son dernier envoi (pas d'addition
-- en double), avec des plafonds et un rejet des valeurs absurdes.
------------------------------------------------------------------
local COMM = "OWDROP1"
-- v0.90 : les mesures partent avec "E|" ; les "D|" des anciennes versions (objets jamais comptes) sont ignores
local MAX_K, MAX_PEERS = 2000, 150
local peerSum
local function RebuildPeerSum()
    peerSum = {}
    for item, kn in pairs(ns.BakedDrops or {}) do peerSum[item] = { kn[1], kn[2] } end
    local from = WarpathDropDB and WarpathDropDB._from
    if not from then return end
    for _, rec in pairs(from) do
        for item, kn in pairs(rec.d or {}) do
            local t = peerSum[item] or { 0, 0 }
            t[1], t[2] = t[1] + kn[1], t[2] + kn[2]
            peerSum[item] = t
        end
    end
end
function ns.PeerDrops(item)
    if not peerSum then RebuildPeerSum() end
    local t = peerSum[item]
    if not t then return 0, 0 end
    return t[1], t[2]
end
local function ShareOn() return WarpathDropDB and WarpathDropDB._share ~= false end
local function OnDropMessage(msg, sender)
    if not ShareOn() or type(msg) ~= "string" or msg:sub(1, 2) ~= "E|" then return end
    local me = UnitName and UnitName("player")
    local short = sender and sender:match("^([^%-]+)") or sender
    if not short or short == me then return end
    local rec = { t = time and time() or 0, d = {} }
    local n = 0
    for item, k, got in msg:gmatch("(%d+):(%d+):(%d+)") do
        item, k, got = tonumber(item), tonumber(k), tonumber(got)
        if item and k and got and k >= 3 and k <= MAX_K and got <= k * 2 then
            rec.d[item] = { k, got }; n = n + 1
        end
        if n >= 60 then break end
    end
    if n == 0 then return end
    WarpathDropDB._from = WarpathDropDB._from or {}
    local old = WarpathDropDB._from[short]
    if old then for it, kn in pairs(old.d or {}) do if not rec.d[it] then rec.d[it] = kn end end end
    WarpathDropDB._from[short] = rec
    -- trop de joueurs memorises : on oublie le plus ancien
    local cnt, oldest, ot = 0, nil, math.huge
    for nm, r in pairs(WarpathDropDB._from) do cnt = cnt + 1; if (r.t or 0) < ot then oldest, ot = nm, r.t or 0 end end
    if cnt > MAX_PEERS and oldest then WarpathDropDB._from[oldest] = nil end
    peerSum = nil
end
local lastShare = {}
local function ShareDrops(channel)
    if not ShareOn() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) or not WarpathDropDB then return end
    local now = GetTime and GetTime() or 0
    if lastShare[channel] and now - lastShare[channel] < 300 then return end
    lastShare[channel] = now
    local parts = {}
    for item, st in pairs(WarpathDropDB) do
        if type(item) == "number" and type(st) == "table" and (st.k or 0) >= 3 then
            parts[#parts + 1] = item .. ":" .. math.min(st.k, MAX_K) .. ":" .. math.min(st.n or 0, st.k * 2)
        end
    end
    -- messages de 240 caracteres au plus, espaces d'une seconde
    local msgs, cur = {}, "E|"
    for _, p in ipairs(parts) do
        if #cur + #p + 1 > 240 then msgs[#msgs + 1] = cur; cur = "E|" end
        cur = cur .. p .. "|"
    end
    if cur ~= "E|" then msgs[#msgs + 1] = cur end
    for i, m in ipairs(msgs) do
        if i > 20 then break end
        local function send() pcall(C_ChatInfo.SendAddonMessage, COMM, m, channel) end
        if C_Timer and C_Timer.After then C_Timer.After(i, send) else send() end
    end
end
ns.ShareDrops, ns.OnDropMessage, ns.COMM, ns.ShareOn = ShareDrops, OnDropMessage, COMM, ShareOn


------------------------------------------------------------------
-- Version : on annonce la sienne au groupe / a la guilde ; si quelqu'un a plus recent, on le dit une fois.
------------------------------------------------------------------
local function VerNum(v)
    local a, b, c = tostring(v or ""):match("^(%d+)%.?(%d*)%.?(%d*)")
    return (tonumber(a) or 0) * 10000 + (tonumber(b) or 0) * 100 + (tonumber(c) or 0)
end
local warned, lastV = false, {}
function ns.SendVersion(channel, mine)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local now = GetTime and GetTime() or 0
    if lastV[channel] and now - lastV[channel] < 300 then return end
    lastV[channel] = now
    pcall(C_ChatInfo.SendAddonMessage, COMM, "V|" .. tostring(mine), channel)
end
function ns.OnVersion(theirs, sender, mine)
    if warned or not theirs:match("^%d") then return end
    if VerNum(theirs) > VerNum(mine) then
        warned = true
        local who = sender and sender:match("^([^%-]+)") or "?"
        print("|cffcdbb8eWarpath|r: " .. ns.T("newVersion", theirs, who))
    end
end
