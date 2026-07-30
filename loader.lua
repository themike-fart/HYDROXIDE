local DEFAULT_REPO = getgenv().hydroxide_repo or "heisenburgah/HYDROXIDE"
local DEFAULT_BRANCH = getgenv().hydroxide_branch or "main"

local gameId = game.GameId
if gameId == 1087859240 then
    pcall(function()
        loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/".. DEFAULT_REPO .."/"..DEFAULT_BRANCH"/ROGUE/rogue_ui.lua?nonce="..tostring(math.random()),
            true
        ))()
    end)
elseif gameId == 7359098240 then
    pcall(function()
        loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/".. DEFAULT_REPO .."/"..DEFAULT_BRANCH.."/ROGUE_BATTLEGROUNDS/rlb.lua?nonce="..tostring(math.random()),
            true
        ))()
    end)
end
