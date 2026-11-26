RemoveCallbacks()

local WHITELIST = {
    3154658,
    2629682,
    2633322,
}

local C = {
    main = "`p",
    accent = "`5",
    num = "`w",
    dim = "`o",
}

local gating = false
local gotId = nil

local function clean(s)
    s = tostring(s or "")
    s = s:gsub("`.", "")
    s = s:gsub("^@", "")
    return s
end

local function field(p, name)
    local ok, v = pcall(function() return p[name] end)
    if ok then return v end
    return nil
end

local function my_name()
    local me = GetLocal()
    if me then
        return me.name or me.nickname or me.display_name or "Player"
    end
    return "Player"
end

local function popup(d)
    SendVarlist({ [0] = "OnDialogRequest", [1] = d, netid = -1 })
end

local function is_whitelisted(id)
    for _, allowed in ipairs(WHITELIST) do
        if tonumber(allowed) == tonumber(id) then
            return true
        end
    end
    return false
end

local function gate_dialog(varlist)
    if not gating then return false end
    if varlist[0] ~= "OnDialogRequest" then return false end

    local dlg = varlist[1]
    if not dlg then return false end

    local text = dlg:gsub("`.", "")
    local id = text:match("UserID:%s*(%d+)")
    if id then
        gotId = tonumber(id)
        return true
    end

    return false
end

AddCallback("gate_dialog", "OnVarlist", gate_dialog)

local function read_userid()
    local me = GetLocal()
    if not me then return nil end

    for _, key in ipairs({ "userid", "user_id", "userID", "uid", "UserID" }) do
        local v = tonumber(field(me, key))
        if v then return v end
    end

    local netid = field(me, "netid")
    if not netid then return nil end

    gating = true
    gotId = nil
    SendPacket(2, "action|wrench\n|netid|" .. netid)

    local waited = 0
    while not gotId and waited < 3000 do
        Sleep(100)
        waited = waited + 100
    end

    gating = false
    return gotId
end

local function start(userid)
    local IDS = {
        dl = 1796,
        bgl = 7188,
        abso = 18138,
    }

    local LABELS = {
        [1796] = "Diamond Lock",
        [7188] = "Blue Gem Lock",
        [18138] = "Absolute Lock",
    }

    local COMMANDS = {
        { cmd = "/sc",   icon = 32,    desc = "Show the full list of commands.",              usage = "/sc" },
        { cmd = "/c",    icon = 242,   desc = "Simple calculator, says the result in chat.",  usage = "/c <2.5x3>" },
        { cmd = "/dl",   icon = 1796,  desc = "Drop your Diamond Locks.",                     usage = "/dl or /dl <amount>" },
        { cmd = "/bgl",  icon = 7188,  desc = "Drop your Blue Gem Locks.",                    usage = "/bgl or /bgl <amount>" },
        { cmd = "/abso", icon = 18138, desc = "Drop your Absolute Locks.",                    usage = "/abso or /abso <amount>" },
        { cmd = "/bal",  icon = 7188,  desc = "Check your bank balance.",                     usage = "/bal" },
        { cmd = "/depo", icon = 7188,  desc = "Deposit Blue Gem Locks into the bank.",        usage = "/depo or /depo <amount>" },
        { cmd = "/wd",   icon = 7188,  desc = "Withdraw from the bank (100 = 1 Absolute Lock).", usage = "/wd <amount>" },
        { cmd = "/tf",   icon = 7188,  desc = "Fast bank transfer to a player.",              usage = "/tf <player name> <amount>" },
        { cmd = "/tpd",  icon = 18,    desc = "Punch a tile to collect the locks on it.",     usage = "/tpd (use again to turn off)" },
        { cmd = "/reme", icon = 32,    desc = "Spin check: first digit + last digit, keeps the last digit of the sum.", usage = "/reme (use again to turn off)" },
        { cmd = "/leme", icon = 32,    desc = "Same as /reme.",                               usage = "/leme (use again to turn off)" },
        { cmd = "/qeme", icon = 32,    desc = "Spin check: shows only the last digit.",       usage = "/qeme (use again to turn off)" },
    }

    local LOCKS = {
        [1796] = true,
        [7188] = true,
        [18138] = true,
    }

    local busy = false
    local mode = nil
    local tpd = false

    local wealth = nil
    local balGot = false
    local tfWaiting = false
    local tfFailed = false

    local function parse(packet)
        local text = packet:match("action|input\n|text|([^\n]*)")
        if not text then return nil end
        local cmd, rest = text:match("^(/%S+)%s*(.*)$")
        return cmd, rest
    end

    local function say(msg)
        SendPacket(2, "action|input\n|text|" .. msg)
    end

    local function note(msg)
        log(C.main .. msg)
    end

    local function error_msg(msg)
        log("`4" .. msg)
        SendVarlist({ [0] = "OnTextOverlay", [1] = "`4" .. msg, netid = -1 })
    end

    local function announce(action, amount, label)
        say(C.main .. "[" .. C.accent .. my_name() .. C.main .. "] " ..
            C.main .. action .. " " .. C.num .. amount .. " " .. C.accent .. label)
    end

    local function split_text(amount)
        local abso = math.floor(amount / 100)
        local bgl = amount % 100

        local parts = {}
        if abso > 0 then
            parts[#parts + 1] = C.num .. abso .. " " .. C.accent .. LABELS[IDS.abso]
        end
        if bgl > 0 then
            parts[#parts + 1] = C.num .. bgl .. " " .. C.accent .. LABELS[IDS.bgl]
        end

        return table.concat(parts, C.main .. " and ")
    end

    local function show_commands()
        local d = "set_default_color|" .. C.dim .. "\n" ..
            "add_label_with_icon|big|" .. C.main .. "CSN Helper - Command List``|left|32|\n" ..
            "add_smalltext|" .. C.dim .. "This helper has " .. #COMMANDS .. " commands!|\n" ..
            "add_spacer|small|\n"

        for _, c in ipairs(COMMANDS) do
            d = d ..
                "add_label_with_icon|small|" .. C.main .. "[" .. C.accent .. c.cmd .. C.main .. "] " ..
                C.dim .. "- " .. c.desc .. "``|left|" .. c.icon .. "|\n" ..
                "add_smalltext|" .. C.dim .. "Usage: " .. C.num .. c.usage .. "|\n" ..
                "add_spacer|small|\n"
        end

        d = d .. "add_quick_exit|\n" .. "end_dialog|csn_help|Close||\n"

        popup(d)
    end

    local function calc_spin(number, kind)
        local s = tostring(number)
        local first = tonumber(s:sub(1, 1))
        local last = tonumber(s:sub(-1))

        if kind == "QEME" then
            return last
        end

        if #s == 1 then
            return first
        end

        return (first + last) % 10
    end

    local function calculate(expr)
        if not expr or expr == "" then
            log("`4Usage: /c <math>  e.g. /c 5*20+3")
            return
        end

        local c = expr:gsub(",", ""):gsub("[xX]", "*"):gsub("%s+", "")

        if c:find("[^%d%.%+%-%*/%%%^%(%)]") then
            log("`4Invalid characters. Use numbers and + - * / % ^ ( )")
            return
        end

        local fn = load("return " .. c)
        if not fn then
            log("`4Invalid expression.")
            return
        end

        local ok, result = pcall(fn)
        if not ok or type(result) ~= "number" then
            log("`4Could not calculate that.")
            return
        end

        if result == math.floor(result) then
            result = string.format("%d", result)
        else
            result = string.format("%.4f", result):gsub("0+$", ""):gsub("%.$", "")
        end

        say(C.accent .. expr .. " " .. C.main .. "= " .. C.num .. result)
    end

    local function drop(id, amount)
        local have = GetItemCount(id)
        if have <= 0 then
            log("`4You don't have that item.")
            return
        end
        if not amount or amount <= 0 or amount > have then
            amount = have
        end
        busy = true
        SendPacket(2, "action|drop\n|itemID|" .. id)
        Sleep(150)
        SendPacket(2,
            "action|dialog_return\n" ..
            "dialog_name|drop_item\n" ..
            "itemID|" .. id .. "|\n" ..
            "count|" .. amount
        )
        announce("Dropped", amount, LABELS[id] or "item")
        Sleep(300)
        busy = false
    end

    local function balance()
        if busy then
            log("`6Busy, try again in a moment.")
            return
        end

        busy = true
        balGot = false

        SendPacket(2, "action|dialog_return\ndialog_name|my_bank_account\nbuttonClicked|withdraw\n")

        local waited = 0
        while not balGot and waited < 2000 do
            Sleep(100)
            waited = waited + 100
        end

        Sleep(200)
        busy = false

        if not balGot or wealth == nil then
            error_msg("Could not read your bank balance.")
            return
        end

        local text
        if wealth <= 0 then
            text = C.num .. "0"
        else
            text = split_text(wealth)
        end

        log(C.main .. "Bank balance: " .. text)
        SendVarlist({ [0] = "OnTextOverlay", [1] = C.main .. "Bank balance: " .. text, netid = -1 })
    end

    local function deposit(amount)
        if not amount or amount <= 0 then
            log("`4Nothing to deposit.")
            return
        end
        busy = true
        SendPacket(2, "action|dialog_return\ndialog_name|my_bank_account\nbuttonClicked|deposit\n")
        Sleep(400)
        SendPacket(2,
            "action|dialog_return\n" ..
            "dialog_name|my_bank_account\n" ..
            "buttonClicked|depo_true\n" ..
            "bgl_|" .. amount .. "\n"
        )
        say(C.main .. "Deposited " .. split_text(amount))
        Sleep(400)
        busy = false
    end

    local function withdraw(amount)
        if not amount or amount <= 0 then
            log("`4Usage: /wd <amount>")
            return
        end

        busy = true
        SendPacket(2, "action|dialog_return\ndialog_name|my_bank_account\nbuttonClicked|withdraw\n")
        Sleep(400)
        SendPacket(2,
            "action|dialog_return\n" ..
            "dialog_name|my_bank_account\n" ..
            "buttonClicked|wd_true\n" ..
            "wd_amount|" .. amount .. "\n"
        )
        say(C.main .. "Withdrawn " .. split_text(amount))
        Sleep(400)
        busy = false
    end

    local function transfer(name, amount)
        if not name or name == "" or not amount or amount <= 0 then
            log("`4Usage: /tf <player name> <amount>")
            return
        end

        if wealth and amount > wealth then
            error_msg("Not enough BGL/Abso to transfer " .. amount .. ".")
            return
        end

        busy = true
        tfFailed = false
        tfWaiting = true

        SendPacket(2, "action|dialog_return\ndialog_name|my_bank_account\nbuttonClicked|transfer\n")
        Sleep(400)
        SendPacket(2,
            "action|dialog_return\n" ..
            "dialog_name|my_bank_account\n" ..
            "buttonClicked|tf_true\n" ..
            "tf_amount|" .. amount .. "\n" ..
            "tf_name|" .. name .. "\n"
        )
        Sleep(600)

        tfWaiting = false

        if tfFailed then
            error_msg("Not enough BGL/Abso to transfer " .. amount .. ".")
        else
            if wealth then
                wealth = math.max(0, wealth - amount)
            end
            say(C.main .. "Transferred " .. split_text(amount) .. C.main .. " to " .. C.accent .. name)
        end

        Sleep(300)
        busy = false
    end

    local function set_mode(name)
        if mode == name then
            mode = nil
            log("`4" .. name .. ": `wOFF")
        else
            mode = name
            note(name .. ": `wON")
        end
    end

    local function obj_field(obj, ...)
        for _, key in ipairs({ ... }) do
            local v = field(obj, key)
            if v ~= nil then return v end
        end
        return nil
    end

    local function get_objects()
        local names = { "GetObjectList", "GetObjects", "GetWorldObjects", "GetFloatingItems", "GetDroppedItems" }
        for _, name in ipairs(names) do
            local fn = _G[name]
            if fn then
                local ok, result = pcall(fn)
                if ok and type(result) == "table" then
                    return result
                end
            end
        end
        return nil
    end

    local function take_at(tile_x, tile_y)
        local objects = get_objects()
        if not objects then
            log("`4Could not read floating items.")
            return
        end

        for _, obj in pairs(objects) do
            local id = obj_field(obj, "id", "item_id", "itemID")
            if LOCKS[id] then
                local ox = obj_field(obj, "pos_x", "x") or 0
                local oy = obj_field(obj, "pos_y", "y") or 0
                if math.floor((ox + 8) / 32) == tile_x and math.floor((oy + 8) / 32) == tile_y then
                    local oid = obj_field(obj, "oid", "uid", "object_id", "id2")
                    SendPacketRaw({
                        type = 11,
                        value = oid,
                        int_data = oid,
                        pos_x = ox,
                        pos_y = oy,
                    })
                    Sleep(50)
                end
            end
        end
    end

    local function raw_hook(packet)
        if not tpd then return false end

        if field(packet, "type") ~= 3 then return false end
        if field(packet, "int_data") ~= 18 then return false end

        local tx = field(packet, "int_x")
        local ty = field(packet, "int_y")
        if tx and ty then
            RunThread(function() take_at(tx, ty) end)
        end

        return false
    end

    local function command_handler(type, packet)
        if type ~= 2 then return false end

        local cmd, rest = parse(packet)
        if not cmd then return false end

        local a = tonumber(rest:match("^(%d+)"))

        if cmd == "/sc" then
            show_commands()
            return true
        elseif cmd == "/c" then
            RunThread(function() calculate(rest) end)
            return true
        elseif cmd == "/dl" then
            RunThread(function() drop(IDS.dl, a) end)
            return true
        elseif cmd == "/bgl" then
            RunThread(function() drop(IDS.bgl, a) end)
            return true
        elseif cmd == "/abso" then
            RunThread(function() drop(IDS.abso, a) end)
            return true
        elseif cmd == "/bal" then
            RunThread(balance)
            return true
        elseif cmd == "/depo" then
            local amount = a or GetItemCount(IDS.bgl)
            RunThread(function() deposit(amount) end)
            return true
        elseif cmd == "/wd" then
            RunThread(function() withdraw(a or 0) end)
            return true
        elseif cmd == "/tf" then
            local name, amt = rest:match("^@?(%S+)%s+(%d+)")
            RunThread(function() transfer(name, tonumber(amt)) end)
            return true
        elseif cmd == "/tpd" then
            tpd = not tpd
            if tpd then
                note("Punch Take: `wON")
            else
                log("`4Punch Take: `wOFF")
            end
            return true
        elseif cmd == "/reme" then
            set_mode("REME")
            return true
        elseif cmd == "/leme" then
            set_mode("LEME")
            return true
        elseif cmd == "/qeme" then
            set_mode("QEME")
            return true
        end

        return false
    end

    local function read_wealth(dlg)
        local text = dlg:gsub("`.", "")
        local line = text:match("Your Wealth:%s*([^|\n]*)")
        if not line then return end

        if line:find("too poor") then
            wealth = 0
            balGot = true
            return
        end

        local abso = tonumber(line:match("(%d+)%s+Absolute")) or 0
        local bgl = tonumber(line:match("(%d+)%s+Blue")) or 0
        wealth = abso * 100 + bgl
        balGot = true
    end

    local function hide_dialogs(varlist)
        if varlist[0] == "OnDialogRequest" and varlist[1] then
            local dlg = varlist[1]

            if dlg:find("my_bank_account") then
                read_wealth(dlg)
            end

            if tfWaiting then
                local low = dlg:gsub("`.", ""):lower()
                if low:find("not enough") or low:find("insufficient") or low:find("don't have enough") then
                    tfFailed = true
                end
            end

            if busy and (dlg:find("my_bank_account") or dlg:find("drop_item")) then
                return true
            end
        end
        return false
    end

    local function response_check(varlist)
        if not tfWaiting then return false end
        if varlist[0] ~= "OnConsoleMessage" and varlist[0] ~= "OnTextOverlay" then return false end
        if not varlist[1] then return false end

        local low = tostring(varlist[1]):gsub("`.", ""):lower()
        if low:find("not enough") or low:find("insufficient") or low:find("don't have enough") then
            tfFailed = true
        end
        return false
    end

    local function collect_check(varlist)
        if varlist[0] ~= "OnConsoleMessage" then return false end
        if not varlist[1] then return false end

        local msg = varlist[1]:gsub("`.", "")
        if not msg:find("^Collected") then return false end

        for _, id in ipairs({IDS.dl, IDS.bgl, IDS.abso}) do
            local label = LABELS[id]
            if msg:find(label, 1, true) then
                local count = msg:match("Collected%s+(%d+)%s+" .. label) or "1"
                announce("Collected", count, label)
                return false
            end
        end

        return false
    end

    local function fast_spin_check(varlist)
        if varlist[0] ~= "OnTalkBubble" then return false end
        if not varlist[2] or not varlist[2]:find("spun the wheel and got") then return false end
        if varlist[1] == -1 then return false end

        for _, player in pairs(GetPlayers()) do
            if varlist[1] == player.netid then
                local text
                if varlist[2]:find("CP:") then
                    local _, end_pos = string.find(varlist[2], "=")
                    text = "`0[ `4FAKE `0] " .. string.sub(varlist[2], (end_pos or 0) + 1)
                else
                    text = "`0[ `2REAL `0] " .. varlist[2]

                    if mode then
                        local stripped = varlist[2]:gsub("`.", "")
                        local number = tonumber(stripped:match("spun the wheel and got (%d+)"))
                        if number then
                            text = text .. " " .. C.main .. "[" .. C.accent .. mode .. ": " ..
                                C.num .. calc_spin(number, mode) .. C.main .. "]"
                        end
                    end
                end
                SendVarlist({
                    [0] = "OnTalkBubble",
                    [1] = varlist[1],
                    [2] = text,
                    [3] = -1,
                    netid = -1,
                })
                return true
            end
        end

        return false
    end

    AddCallback("csn_cmd", "OnPacket", command_handler)
    AddCallback("csn_raw", "OnRawPacket", raw_hook)
    AddCallback("csn_hide", "OnVarlist", hide_dialogs)
    AddCallback("csn_response", "OnVarlist", response_check)
    AddCallback("csn_collect", "OnVarlist", collect_check)
    AddCallback("spin_name", "OnVarlist", fast_spin_check)
end

RunThread(function()
    local userid = read_userid()

    if not userid then
        popup(
            "set_default_color|`o\n" ..
            "add_label_with_icon|big|`4Access Denied``|left|18|\n" ..
            "add_spacer|small|\n" ..
            "add_textbox|`oCould not read your UserID.|\n" ..
            "add_spacer|small|\n" ..
            "add_quick_exit|\n" ..
            "end_dialog|access_denied|Close||\n"
        )
        log("`4Access Denied. Could not read your UserID.")
        return
    end

    if not is_whitelisted(userid) then
        popup(
            "set_default_color|`o\n" ..
            "add_label_with_icon|big|`4Access Denied``|left|18|\n" ..
            "add_spacer|small|\n" ..
            "add_textbox|`oYou are not whitelisted to use this script.|\n" ..
            "add_spacer|small|\n" ..
            "add_textbox|`oYour UserID: `w" .. userid .. "|\n" ..
            "add_spacer|small|\n" ..
            "add_quick_exit|\n" ..
            "end_dialog|access_denied|Close||\n"
        )
        log("`4Access Denied. UserID: " .. userid)
        return
    end

    popup(
        "set_default_color|`o\n" ..
        "add_label_with_icon|big|`2Access Granted``|left|18|\n" ..
        "add_spacer|small|\n" ..
        "add_textbox|" .. C.main .. "Welcome, " .. C.accent .. clean(my_name()) .. C.main .. "!|\n" ..
        "add_textbox|`oUse " .. C.accent .. "/sc `oto check the commands.|\n" ..
        "add_spacer|small|\n" ..
        "add_quick_exit|\n" ..
        "end_dialog|access_granted|Close||\n"
    )

    start(userid)
end)
