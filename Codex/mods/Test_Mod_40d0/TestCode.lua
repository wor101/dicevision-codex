local mod = dmhub.GetModLoading()
Commands.hello = function(args)
    if #dmhub.selectedTokens == 0 then    
        print("DBG: No tokens selected")
    else
        for _,token in ipairs(dmhub.selectedTokens) do
            if token.name == nil then
                print("DBG: Hello there my anonymous friend you have", token.properties:CurrentHitpoints(), "hitpoints")
            else
                print("DBG: Hello there", token.name, "you have", token.properties:CurrentHitpoints(), "hitpoints")
            end
        end
    end
end
