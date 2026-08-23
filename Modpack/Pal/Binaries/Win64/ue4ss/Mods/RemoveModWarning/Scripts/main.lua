-- RemoveModWarning: Suppresses the mod warning popup on the title screen for a clean, instant game boot
local function Log(msg)
    print(string.format("[RemoveModWarning] %s\n", tostring(msg)))
end

-- 1. Auto-suppress / auto-dismiss Title Warning Dialogs
NotifyOnNewObject("/Game/Pal/UI/Title/WBP_Title_WarningDialog.WBP_Title_WarningDialog_C", function(dialog)
    if not dialog or not dialog:IsValid() then return end
    pcall(function()
        dialog:SetVisibility(2) -- Collapsed (Hidden)
        dialog:RemoveFromParent()
        Log("Suppressed WBP_Title_WarningDialog on title screen.")
    end)
end)

-- 2. Hook Generic Pal Mod Warning Dialogs
NotifyOnNewObject("/Game/Pal/UI/Common/WBP_Common_Dialog.WBP_Common_Dialog_C", function(dialog)
    if not dialog or not dialog:IsValid() then return end
    pcall(function()
        local text = dialog:GetFullName()
        if string.find(string.lower(text), "warning") or string.find(string.lower(text), "mod") then
            dialog:SetVisibility(2)
            dialog:RemoveFromParent()
            Log("Auto-dismissed mod warning dialog.")
        end
    end)
end)

-- 3. Register Function Hooks to prevent warning dialog creation
pcall(function()
    RegisterHook("/Script/Pal.PalUIManager:ShowWarningDialog", function(self)
        Log("Blocked PalUIManager:ShowWarningDialog call.")
        return true -- Block execution
    end)
end)

Log("RemoveModWarning loaded successfully.")
