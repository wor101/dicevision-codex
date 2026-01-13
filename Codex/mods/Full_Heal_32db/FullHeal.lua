Commands.fullheal = function(args)
    print("DBG: dmhub variable:", dmhub)
    if #dmhub.selectedTokens == 0 then    
        print("DBG: No tokens selected")
    else
        for _,token in ipairs(dmhub.selectedTokens) do
            local name = token.name or "Anonymous"
            token:ModifyProperties{
description = "Full Heal",
execute = function()
                local amount = token.properties:MaxHitpoints() - token.properties:CurrentHitpoints()
                if amount <= 0 then
                    print("DBG: Token", name, "is already at full hitpoints")
                else
                    token.properties:Heal(amount, "Healed by Full Heal macro")
                end
                print("DBG: Healed", name, "by", amount, "hitpoints to full health")
            end,
            }
        end
    end
end
