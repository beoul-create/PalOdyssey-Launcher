local ShopCatalog = {}

function ShopCatalog.GetItem(Config, Key)
    if not Config or not Config.ShopItems or not Key then return nil end
    return Config.ShopItems[Key:lower()]
end

function ShopCatalog.GetRecycleRate(Config, ItemId)
    if not Config or not Config.RecycleRates or not ItemId then return 0 end
    return Config.RecycleRates[ItemId] or 0
end

return ShopCatalog
