--[[
    DiceVision Dockable Panel
    Provides a clickable UI for triggering physical dice rolls via DiceVision.
    Requires DiceVision.lua to be loaded first.
]]

local _ = dmhub.GetModLoading() -- luacheck: ignore

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
    minHeight = 100,
    maxHeight = 100,
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
        width = "auto",
        height = "auto",
        autosizeimage = true,
        maxWidth = 120,
        maxHeight = 60,
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
    {
        classes = {"dvButton", "parent:hover"},
        scale = 1.1,
        brightness = 1.2,
    },
    -- Toggle button styles
    {
        classes = "dvToggle",
        bgimage = "panels/square.png",
        bgcolor = "#2d7a2d",
        width = "auto",
        height = 22,
        halign = "center",
        valign = "center",
        cornerRadius = 4,
        hpad = 12,
        vpad = 2,
    },
    {
        classes = {"dvToggle", "paused"},
        bgcolor = "#7a5a1d",
    },
    {
        classes = {"dvToggle", "disabled"},
        bgcolor = "#333333",
        brightness = 0.3,
    },
    {
        classes = {"dvToggle", "hover"},
        brightness = 1.2,
    },
}

-- Connect popup styles. Popups are a styling island (popupsInheritStyles
-- defaults false), so the connect popup carries its own style table rather
-- than relying on diceVisionPanelStyles above.
local connectPopupStyles = {
    {
        classes = "dvConnectInput",
        bgimage = "panels/square.png",
        bgcolor = "#0d0d0dff",
        color = "white",
        width = 140,
        height = 24,
        fontSize = 12,
        pad = 4,
        cornerRadius = 3,
        borderWidth = 1,
        borderColor = "#555555",
    },
    {
        classes = "dvConnectBtn",
        bgimage = "panels/square.png",
        bgcolor = "#2d7a2d",
        color = "white",
        width = 140,
        height = 24,
        halign = "center",
        valign = "center",
        cornerRadius = 4,
        fontSize = 12,
    },
    {
        classes = {"dvConnectBtn", "hover"},
        brightness = 1.2,
    },
    {
        classes = {"dvConnectBtn", "disabled"},
        bgcolor = "#333333",
        brightness = 0.3,
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
    local statusShadow
    local diceButton
    local toggleButton
    local toggleLabel

    local updateState = function()
        if diceButton then
            diceButton:SetClass("disconnected", not DiceVision.connected)
            diceButton:SetClass("waiting", DiceVision.panelWaitingForRoll)
        end
        if statusLabel then
            local text
            if not DiceVision.connected then
                text = "Disconnected"
            elseif DiceVision.panelWaitingForRoll then
                text = "Rolling..."
            elseif DiceVision.mode == "off" then
                text = "Paused"
            else
                text = "Roll Dice"
            end
            statusLabel.text = text
            statusShadow.text = text
        end
        if toggleButton then
            local isConnected = DiceVision.connected
            local isPaused = isConnected and DiceVision.mode == "off"
            toggleButton:SetClass("disabled", not isConnected)
            toggleButton:SetClass("paused", isPaused)
            if not isConnected then
                toggleButton.selfStyle.bgcolor = "#333333"
            elseif isPaused then
                toggleButton.selfStyle.bgcolor = "#7a5a1d"
            else
                toggleButton.selfStyle.bgcolor = "#2d7a2d"
            end
            if toggleLabel then
                if not isConnected then
                    toggleLabel.text = "---"
                elseif isPaused then
                    toggleLabel.text = "Paused"
                else
                    toggleLabel.text = "Active"
                end
            end
        end
    end

    -- Builds the connect popup spawned from the (disconnected) dice button.
    -- hostPanel is the dice button so the async connect callback can close the
    -- popup by clearing hostPanel.popup. The connect contract itself lives in
    -- DiceVision.connect; this just gathers the code and reflects status.
    local CreateConnectPopup = function(hostPanel)
        local input
        local statusLine
        local connectButton
        local connecting = false

        local doConnect = function()
            if connecting then
                return
            end
            local code = (input and input.text or ""):gsub("%s+", "")
            if code == "" then
                statusLine.text = "Enter a session code"
                return
            end
            connecting = true
            connectButton:SetClass("disabled", true)
            statusLine.text = "Connecting..."
            DiceVision.connect(code, function(success, result)
                connecting = false
                if success then
                    if hostPanel then
                        hostPanel.popup = nil
                    end
                else
                    connectButton:SetClass("disabled", false)
                    statusLine.text = "Failed: " .. tostring(result)
                end
            end)
        end

        input = gui.Input{
            classes = "dvConnectInput",
            placeholderText = "session code",
            lineType = "SingleLine",
            selectAllOnFocus = true,
            characterLimit = 16,
            text = "",
            submit = function(element) doConnect() end,
        }

        statusLine = gui.Label{
            interactable = false,
            width = 140,
            height = "auto",
            halign = "center",
            fontSize = 9,
            color = "#cccccc",
            text = "",
        }

        connectButton = gui.Panel{
            classes = "dvConnectBtn",
            hover = gui.Tooltip{
                text = "Connect to this DiceVision session",
            },
            click = function(panel) doConnect() end,

            gui.Label{
                interactable = false,
                width = "100%",
                height = "100%",
                halign = "center",
                valign = "center",
                color = "white",
                fontSize = 12,
                text = "Connect",
            },
        }

        return gui.Panel{
            styles = connectPopupStyles,
            flow = "vertical",
            width = "auto",
            height = "auto",
            pad = 8,
            bgimage = "panels/square.png",
            bgcolor = "#1a1a1aff",
            cornerRadius = 6,
            borderWidth = 1,
            borderColor = "#666666",
            captureEscape = true,
            escapePriority = 10,
            escape = function(element)
                if hostPanel then
                    hostPanel.popup = nil
                end
            end,

            gui.Label{
                interactable = false,
                width = "auto",
                height = "auto",
                halign = "center",
                fontSize = 11,
                bold = true,
                color = "white",
                text = "DiceVision",
                bmargin = 4,
            },
            input,
            gui.Panel{ width = 140, height = 4 },
            connectButton,
            statusLine,
        }
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
                -- Disconnected: open (or toggle closed) the connect popup
                -- anchored to the dice button instead of the old chat hint.
                if panel.popup ~= nil then
                    panel.popup = nil
                    return
                end
                panel.popupPositioning = "panel"
                panel.popup = CreateConnectPopup(panel)
                return
            end

            if DiceVision.panelWaitingForRoll then
                chat.Send("[DiceVision] Already waiting for dice...")
                return
            end

            DiceVision.panelRequestId = DiceVision.generateRequestId()
            DiceVision.panelWaitingForRoll = true
            DiceVision.panelPollStartTime = dmhub.Time() * 1000

            -- Capture selected token for roll attribution
            if dmhub.currentToken ~= nil then
                DiceVision.panelTokenId = dmhub.currentToken.charid
            else
                local selectedTokens = dmhub.selectedOrPrimaryTokens
                if selectedTokens and #selectedTokens > 0 then
                    DiceVision.panelTokenId = selectedTokens[1].charid
                else
                    DiceVision.panelTokenId = nil
                end
            end

            if not DiceVision.isPolling then
                DiceVision.startPolling()
            end

            chat.Send("[DiceVision] Roll your physical dice now...")
            updateState()
        end,

        gui.Panel{
            interactable = false,
            width = "auto",
            height = "auto",
            autosizeimage = true,
            maxWidth = 120,
            maxHeight = 60,
            halign = "center",
            valign = "center",
            bgimage = "ui-icons/dsdice/djordice-2d10.png",
            bgcolor = diceStyle.trimcolor,
        },
    }

    statusShadow = gui.Label{
        interactable = false,
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        fontFace = "Book",
        fontSize = 10,
        color = "black",
        text = "Roll Dice",
        x = 1,
        y = 1,
        styles = {
            {
                classes = "parent:hover",
                scale = 1.1,
            }
        },
    }

    statusLabel = gui.Label{
        interactable = false,
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        fontFace = "Book",
        fontSize = 10,
        color = "white",
        text = "Roll Dice",
        styles = {
            {
                classes = "parent:hover",
                scale = 1.1,
            }
        },
    }

    toggleLabel = gui.Label{
        interactable = false,
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        fontFace = "Book",
        fontSize = 10,
        bold = true,
        color = "white",
        text = "Active",
    }

    toggleButton = gui.Panel{
        classes = "dvToggle",
        bgimage = "panels/square.png",
        bgcolor = "#2d7a2d",
        width = 80,
        height = 22,
        halign = "center",
        valign = "center",
        cornerRadius = 4,
        hpad = 12,
        vpad = 2,

        hover = gui.Tooltip{
            text = "Toggle roll interception on/off",
            valign = "top",
        },

        click = function(panel)
            if not DiceVision.connected then
                return
            end
            -- The toggle contract (compute opposite mode, pass verbose on
            -- replace, emit confirmation) lives in DiceVision._panelToggle
            -- so it can be exercised directly by tests.
            DiceVision._panelToggle()
            updateState()
        end,

        gui.Panel{
            interactable = false,
            width = "100%",
            height = "100%",
            halign = "center",
            valign = "center",
            toggleLabel,
        },
    }

    local resultPanel = gui.Panel{
        width = "100%",
        height = "100%",
        styles = diceVisionPanelStyles,
        bgimage = "panels/square.png",
        bgcolor = "clear",

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
            flow = "vertical",
            width = "100%",
            height = "100%",

            -- Row 1: dice button + status labels
            gui.Panel{
                width = "100%",
                height = 68,
                halign = "center",
                valign = "center",
                diceButton,
                statusShadow,
                statusLabel,
            },

            -- Row 2: toggle button
            gui.Panel{
                width = "100%",
                height = 28,
                halign = "center",
                valign = "center",
                toggleButton,
            },
        },
    }

    updateState()
    return resultPanel
end

print("DV: DVDicePanel loaded")
