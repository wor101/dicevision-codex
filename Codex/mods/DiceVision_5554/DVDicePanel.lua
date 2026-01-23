--[[
    DiceVision Dockable Panel
    Provides a clickable UI for triggering physical dice rolls via DiceVision.
    Requires DiceVision.lua to be loaded first.
]]

local mod = dmhub.GetModLoading()

-- ============================================================================
-- Panel Registration
-- ============================================================================

local CreateDiceVisionPanel

DockablePanel.Register{
    name = "DiceVision",
    icon = "ui-icons/dsdice/djordice-2d10.png",
    notitle = true,
    vscroll = false,
    dmonly = false,
    minHeight = 68,
    maxHeight = 68,
    content = function()
        return CreateDiceVisionPanel()
    end,
}

-- ============================================================================
-- Styles
-- ============================================================================

local diceVisionPanelStyles = {
    {
        classes = "dvButton",
        bgcolor = "white",
        width = 60,
        height = 60,
        valign = "center",
        halign = "center",
        saturation = 0.7,
        brightness = 0.4,
    },
    {
        classes = {"dvButton", "disconnected"},
        saturation = 0.3,
        brightness = 0.2,
    },
    {
        classes = {"dvButton", "waiting"},
        saturation = 0.9,
        brightness = 0.8,
    },
    {
        classes = {"dvButton", "hover"},
        scale = 1.1,
        brightness = 1.2,
    },
}

-- ============================================================================
-- Panel Creation
-- ============================================================================

CreateDiceVisionPanel = function()
    local diceStyle = dmhub.GetDiceStyling(
        dmhub.GetSettingValue("diceequipped"),
        dmhub.GetSettingValue("playercolor")
    )

    local statusLabel
    local diceButton

    local updateState = function()
        if diceButton then
            diceButton:SetClass("disconnected", not DiceVision.connected)
            diceButton:SetClass("waiting", DiceVision.panelWaitingForRoll)
        end
        if statusLabel then
            if not DiceVision.connected then
                statusLabel.text = "Disconnected"
            elseif DiceVision.panelWaitingForRoll then
                statusLabel.text = "Rolling..."
            else
                statusLabel.text = "Roll Dice"
            end
        end
    end

    diceButton = gui.Panel{
        classes = "dvButton",
        bgimage = "ui-icons/dsdice/djordice-2d10-filled.png",
        bgcolor = diceStyle.bgcolor,

        hover = gui.Tooltip{
            text = "Click to roll physical dice",
            valign = "top",
        },

        click = function(panel)
            if not DiceVision.connected then
                chat.Send("[DiceVision] Not connected. Use /dv connect <code> first.")
                return
            end

            if DiceVision.panelWaitingForRoll then
                chat.Send("[DiceVision] Already waiting for dice...")
                return
            end

            DiceVision.panelRequestId = DiceVision.generateRequestId()
            DiceVision.panelWaitingForRoll = true
            DiceVision.panelPollStartTime = dmhub.Time() * 1000

            if not DiceVision.isPolling then
                DiceVision.startPolling()
            end

            chat.Send("[DiceVision] Roll your physical dice now...")
            updateState()
        end,

        gui.Panel{
            interactable = false,
            width = "100%",
            height = "100%",
            bgimage = "ui-icons/dsdice/djordice-2d10.png",
            bgcolor = diceStyle.trimcolor,
        },
    }

    statusLabel = gui.Label{
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "bottom",
        fontSize = 10,
        color = "#cccccc",
        text = "Roll Dice",
        bmargin = 2,
    }

    local resultPanel = gui.Panel{
        width = "100%",
        height = "100%",
        styles = diceVisionPanelStyles,
        bgimage = "panels/square.png",
        bgcolor = "clear",
        flow = "vertical",

        thinkTime = 0.2,
        think = function(element)
            updateState()
        end,

        multimonitor = {"diceequipped", "playercolor"},
        monitor = function(element)
            diceStyle = dmhub.GetDiceStyling(
                dmhub.GetSettingValue("diceequipped"),
                dmhub.GetSettingValue("playercolor")
            )
            diceButton.selfStyle.bgcolor = diceStyle.bgcolor
            diceButton.children[1].selfStyle.bgcolor = diceStyle.trimcolor
        end,

        gui.Panel{
            width = "100%",
            height = "80%",
            halign = "center",
            valign = "center",
            diceButton,
        },
        statusLabel,
    }

    updateState()
    return resultPanel
end

print("DV: DVDicePanel loaded")
