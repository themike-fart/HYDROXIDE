local DEFAULT_RAW = getgenv().hydroxide_raw or "https://git.fable.bz/zyu/hydroxide/raw/branch/main/"

local gameId = game.GameId
if gameId == 1087859240 then
    pcall(function()
        loadstring(game:HttpGet(
            DEFAULT_RAW .. "ROGUE/rogue_ui.lua?nonce="..tostring(math.random()),
            true
        ))()
    end)
elseif gameId == 7359098240 then
    pcall(function()
        loadstring(game:HttpGet(
            DEFAULT_RAW .. "ROGUE_BATTLEGROUNDS/rlb.lua?nonce="..tostring(math.random()),
            true
        ))()
    end)
end
