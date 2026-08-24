-- ============================================================================
-- CleanHUD: High-Performance Version Hider & Clean Viewport Suite
-- Safely suppresses version watermarks without global object scanning
-- ============================================================================

local function Log(msg)
    print(string.format("[CleanHUD] %s\n", tostring(msg)))
end

local function CollapseWidget(widget)
    if not widget or not widget.IsValid or not widget:IsValid() then return end
    pcall(function()
        if widget.SetVisibility then
            widget:SetVisibility(2) -- ESlateVisibility::Collapsed
        end
        if widget.SetRenderOpacity then
            widget:SetRenderOpacity(0.0)
        end
        if widget.SetText then
            widget:SetText("")
        end
        if widget.RemoveFromParent then
            widget:RemoveFromParent()
        end
    end)
end

-- 1. Targeted Widget Class Listeners
local VERSION_CLASSES = {
    "/Game/Pal/Blueprint/UI/HUD/WBP_Ingame_Version.WBP_Ingame_Version_C",
    "/Game/Pal/Blueprint/UI/Title/WBP_Title_Version.WBP_Title_Version_C",
    "/Game/Pal/Blueprint/UI/HUD/WBP_IngameVersion.WBP_IngameVersion_C",
    "/Game/Pal/Blueprint/UI/Title/WBP_TitleVersion.WBP_TitleVersion_C",
    "/Game/Pal/Blueprint/UI/Common/WBP_Version.WBP_Version_C",
    "/Game/Pal/Blueprint/UI/Common/WBP_Watermark.WBP_Watermark_C",
    "/Game/Pal/Blueprint/UI/Common/WBP_BuildVersion.WBP_BuildVersion_C"
}

for _, classPath in ipairs(VERSION_CLASSES) do
    pcall(function()
        NotifyOnNewObject(classPath, function(widget)
            CollapseWidget(widget)
            ExecuteWithDelay(30, function() CollapseWidget(widget) end)
            ExecuteWithDelay(150, function() CollapseWidget(widget) end)
        end)
    end)
end

-- 2. Title Screen & InGameHUD Property Cleaners
local function CleanTitleScreen(title)
    if not title or not title:IsValid() then return end
    pcall(function()
        if title.WBP_Title_Version then CollapseWidget(title.WBP_Title_Version) end
        if title.TextBlock_Version then CollapseWidget(title.TextBlock_Version) end
        if title.Text_Version then CollapseWidget(title.Text_Version) end
        if title.TextBlock_Build then CollapseWidget(title.TextBlock_Build) end
        if title.Overlay_Version then CollapseWidget(title.Overlay_Version) end
        if title.CanvasPanel_Version then CollapseWidget(title.CanvasPanel_Version) end
    end)
end

local function CleanInGameHud(hud)
    if not hud or not hud:IsValid() then return end
    pcall(function()
        if hud.WBP_Ingame_Version then CollapseWidget(hud.WBP_Ingame_Version) end
        if hud.BP_PalUIInGameVersion then CollapseWidget(hud.BP_PalUIInGameVersion) end
        if hud.TextBlock_Version then CollapseWidget(hud.TextBlock_Version) end
        if hud.Text_Version then CollapseWidget(hud.Text_Version) end
        if hud.Overlay_Version then CollapseWidget(hud.Overlay_Version) end
    end)
end

pcall(function()
    NotifyOnNewObject("/Game/Pal/Blueprint/UI/Title/WBP_TitleScreen.WBP_TitleScreen_C", function(title)
        CleanTitleScreen(title)
        for _, delay in ipairs({ 30, 100, 300, 800, 2000 }) do
            ExecuteWithDelay(delay, function() CleanTitleScreen(title) end)
        end
    end)
end)

pcall(function()
    NotifyOnNewObject("/Game/Pal/Blueprint/UI/HUD/WBP_InGameHUD.WBP_InGameHUD_C", function(hud)
        CleanInGameHud(hud)
        for _, delay in ipairs({ 30, 100, 300, 800, 2000 }) do
            ExecuteWithDelay(delay, function() CleanInGameHud(hud) end)
        end
    end)
end)

-- Safe periodic sweep targeting specific named HUD containers only
LoopAsync(2000, function()
    pcall(function()
        local huds = FindAllOf("WBP_InGameHUD_C")
        if huds then
            for _, h in ipairs(huds) do CleanInGameHud(h) end
        end
        local titles = FindAllOf("WBP_TitleScreen_C")
        if titles then
            for _, t in ipairs(titles) do CleanTitleScreen(t) end
        end
        local versions = FindAllOf("WBP_Ingame_Version_C")
        if versions then
            for _, v in ipairs(versions) do CollapseWidget(v) end
        end
    end)
    return false
end)

Log("CleanHUD high-performance version hider active.")
