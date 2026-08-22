-- PalworldTuner config -- NIGHTMARE DIFFICULTY PRESET
-- Scales gameplay settings, stamina, survival, and combat damage.
return {
    difficulty_preset = "Nightmare",
    enemy_damage_mult = 2.0,            -- Enemies deal 2x damage
    player_damage_taken_mult = 1.75,    -- Player takes 75% more damage
    player_stamina_decrease_mult = 1.25,-- Faster stamina burn
    player_hunger_depletion_mult = 1.30,-- Higher hunger rate
    pal_stamina_decrease_mult = 1.20,   -- Pal stamina burn in combat
    carry_weight_mult = 1.0,            -- Hardcore vanilla weight limit
    tech_point_mult = 1.0,              -- Vanilla technology point unlocks
    round_up = true,
    log = true,
}
