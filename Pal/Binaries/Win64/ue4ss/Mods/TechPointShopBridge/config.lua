return {
    enabled = true,

    -- VC Merchant Mod 2 must use this exact value for CurrencyItemID.
    currencyItemId = "PalOdyssey_TechPointToken",

    -- The bridge is activated for vendors matching any of these patterns:
    vendorNamePatterns = {
        "VC_Merchant",
        "VCMerchant",
        "Male_Trader",
        "Female_Trader",
        "Trader",
        "Merchant",
        "Shop",
        "PalNPC"
    },

    diagnostics = true,
    watchdogMilliseconds = 2000
}
