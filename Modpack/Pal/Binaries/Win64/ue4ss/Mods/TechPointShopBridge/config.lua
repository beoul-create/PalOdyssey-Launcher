return {
    enabled = true,

    -- VC Merchant Mod 2 must use this exact value for CurrencyItemID.
    currencyItemId = "PalOdyssey_TechPointToken",

    -- The bridge is activated only for vendors whose full object name contains
    -- one of these strings (case-insensitive). Add the exact VC vendor blueprint
    -- name here if its release uses a different prefix.
    vendorNamePatterns = {
        "VC_Merchant",
        "VCMerchant"
    },

    diagnostics = true,
    watchdogMilliseconds = 2000
}
