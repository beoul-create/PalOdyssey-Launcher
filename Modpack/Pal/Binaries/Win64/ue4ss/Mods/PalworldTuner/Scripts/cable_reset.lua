-- Compatibility shim for the retired cable/glider reset experiment.
--
-- The old implementation walked every live CableComponent once per second and
-- four additional times for each mount, dismount, and weapon event. Besides
-- stalling the game thread, it forced hidden components visible after 40 ms,
-- which could leave a glider or other attachment visible after dismounting.
-- Palworld owns these component lifecycles; leaving them alone preserves the
-- native mount/dismount animation and cleanup path.
local CableReset = {}

function CableReset.Init()
    print("[PalworldTuner] Legacy cable/glider reset disabled; native lifecycle restored.")
end

return CableReset
