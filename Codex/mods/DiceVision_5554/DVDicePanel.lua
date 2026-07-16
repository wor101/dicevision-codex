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
    -- Connect call-to-action: blue, distinct from the green/amber Active/Paused
    -- pair so it reads as "establish a session" rather than a toggle face.
    {
        classes = {"dvToggle", "connect"},
        bgcolor = "#2d5a7a",
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
        -- Blue to match the "Connect..." toggle CTA (consistent "connect =
        -- blue"); green is reserved for the connected/Active state.
        bgcolor = "#2d5a7a",
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

-- Settings popup styles (own styling island, like connectPopupStyles).
local settingsPopupStyles = {
    {
        classes = "dvSetHeader",
        color = "#ffd9a0",
        fontSize = 11,
        bold = true,
        width = "auto",
        height = "auto",
        tmargin = 6,
        bmargin = 2,
    },
    {
        classes = "dvSetInfo",
        color = "#cccccc",
        fontSize = 10,
        width = "auto",
        height = "auto",
    },
    {
        classes = "dvSetBtn",
        bgimage = "panels/square.png",
        bgcolor = "#3a3a3a",
        color = "white",
        height = 22,
        width = "auto",
        halign = "center",
        valign = "center",
        cornerRadius = 4,
        hpad = 8,
        vpad = 2,
        fontSize = 11,
    },
    {
        classes = {"dvSetBtn", "hover"},
        brightness = 1.2,
    },
    {
        classes = {"dvSetBtn", "disabled"},
        bgcolor = "#2a2a2a",
        brightness = 0.4,
    },
    {
        classes = {"dvSetBtn", "selected"},
        bgcolor = "#2d5a7a",
    },
    {
        classes = "dvSetInput",
        bgimage = "panels/square.png",
        bgcolor = "#0d0d0dff",
        color = "white",
        height = 22,
        fontSize = 11,
        pad = 3,
        cornerRadius = 3,
        borderWidth = 1,
        borderColor = "#555555",
    },
    {
        classes = "dvSetRemove",
        bgimage = "panels/square.png",
        bgcolor = "#7a2d2d",
        color = "white",
        width = 18,
        height = 18,
        halign = "center",
        valign = "center",
        cornerRadius = 3,
        fontSize = 11,
    },
    {
        classes = {"dvSetRemove", "hover"},
        brightness = 1.3,
    },
}

-- ============================================================================
-- Panel Creation
-- ============================================================================

-- Open the popup built by `factory(hostPanel)` anchored to hostPanel, or close
-- it if already open (click-to-toggle). Shared by the connect toggle and the
-- settings gear so both behave identically.
local function togglePopup(hostPanel, factory)
    if hostPanel.popup ~= nil then
        hostPanel.popup = nil
        return
    end
    hostPanel.popupPositioning = "panel"
    hostPanel.popup = factory(hostPanel)
end

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
            -- When disconnected this button is the Connect call-to-action
            -- (blue, opens the connect popup); when connected it is the
            -- pause/resume toggle (green Active / amber Paused).
            toggleButton:SetClass("connect", not isConnected)
            toggleButton:SetClass("paused", isPaused)
            if not isConnected then
                toggleButton.selfStyle.bgcolor = "#2d5a7a"
            elseif isPaused then
                toggleButton.selfStyle.bgcolor = "#7a5a1d"
            else
                toggleButton.selfStyle.bgcolor = "#2d7a2d"
            end
            if toggleLabel then
                if not isConnected then
                    toggleLabel.text = "Connect..."
                elseif isPaused then
                    toggleLabel.text = "Paused"
                else
                    toggleLabel.text = "Active"
                end
            end
        end
    end

    -- Builds the connect popup spawned from the (disconnected) toggle button.
    -- hostPanel is the toggle button so the async connect callback can close
    -- the popup by clearing hostPanel.popup. The connect contract itself lives
    -- in DiceVision.connect; this just gathers the code and reflects status.
    local CreateConnectPopup = function(hostPanel)
        local input
        local statusLine
        local connectButton
        local popupPanel
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
                -- net.Get is async in production, so the user may have closed
                -- the popup (escape, or re-clicking the toggle) before this
                -- fires. Only touch the popup widgets if this popup is still
                -- the host's active one; otherwise they are detached.
                elseif hostPanel and hostPanel.popup == popupPanel then
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
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
                color = "white",
                fontSize = 12,
                text = "Connect",
            },
        }

        popupPanel = gui.Panel{
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

        return popupPanel
    end

    -- Builds the settings popup spawned from the gear button. hostPanel is the
    -- gear; the popup closes by clearing hostPanel.popup. Config mutations and
    -- diagnostic actions go through the DiceVision.* seams so the popup carries
    -- no logic of its own (matching the connect popup). The status section
    -- refreshes on a think tick because it can change from outside the popup
    -- (chat /dv commands, a poll-timeout disconnect, late hook registration);
    -- the rules controls refresh on demand after each edit so they do not
    -- clobber text the user is typing into the add-mapping inputs.
    local CreateSettingsPopup = function(hostPanel)
        local popupPanel
        local statusInfo, testLine
        local addStatus
        local testing = false
        local clampBtn, clampLabel
        local forcedBtn, forcedLabel
        local cardBtn, cardLabel
        local autoBtn, highBtn, lowBtn, countInput
        local mappingRows
        local addDie, addFrom, addTo
        local rebuildMappingRows
        local typeRows
        local typeFrom, typeTo, typeAddStatus
        local typePanelBtn, typePanelLabel
        local rebuildTypeRows

        local function buildButton(label, onClick)
            return gui.Panel{
                classes = "dvSetBtn",
                click = function(panel) onClick(panel) end,
                gui.Label{
                    interactable = false,
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    valign = "center",
                    color = "white",
                    fontSize = 11,
                    text = label,
                },
            }
        end

        local function refreshStatus()
            local s = DiceVision.getStatus()
            local text = string.format(
                "Connected: %s   Mode: %s\nSession: %s",
                s.connected and "yes" or "no",
                s.mode,
                s.sessionCode or "none"
            )
            if #s.missing > 0 then
                text = text .. "\nMissing hooks: " .. tostring(#s.missing)
            end
            statusInfo.text = text
        end

        local function refreshClamp()
            local on = DiceVision.rules.clampOutOfRange
            clampLabel.text = on and "On" or "Off"
            clampBtn:SetClass("selected", on)
        end

        local function refreshForcedDice()
            local on = DiceVision.useForcedDice
            forcedLabel.text = on and "On" or "Off"
            forcedBtn:SetClass("selected", on)
            local card = DiceVision.forcedDiceChatCard
            cardLabel.text = card and "On" or "Off"
            cardBtn:SetClass("selected", card)
        end

        local function refreshTypePanel()
            local on = DiceVision.rules.typeMappingsOnPanel
            typePanelLabel.text = on and "On" or "Off"
            typePanelBtn:SetClass("selected", on)
        end

        local function refreshKeep()
            local sel = DiceVision.rules.diceSelection
            local mode = sel and sel.keep or "auto"
            autoBtn:SetClass("selected", mode == "auto")
            highBtn:SetClass("selected", mode == "highest")
            lowBtn:SetClass("selected", mode == "lowest")
            -- Count only applies to highest/lowest; disable it in auto mode so a
            -- typed count is not silently ignored.
            countInput.editable = (mode ~= "auto")
        end

        -- Repaint every rules control at once (rebuildMappingRows is a forward-
        -- declared upvalue, assigned below before this is ever called).
        local function refreshAllRules()
            refreshClamp()
            refreshForcedDice()
            refreshTypePanel()
            refreshKeep()
            rebuildMappingRows()
            rebuildTypeRows()
        end

        rebuildMappingRows = function()
            local rows = {}
            for dieType, mappings in pairs(DiceVision.rules.valueMappings) do
                for from, to in pairs(mappings) do
                    -- Close over the specific entry so the remove button stays
                    -- correct after the list is rebuilt.
                    local d, f = dieType, from
                    rows[#rows + 1] = gui.Panel{
                        flow = "horizontal",
                        width = "100%",
                        height = "auto",
                        valign = "center",
                        gui.Label{
                            classes = "dvSetInfo",
                            width = "100%-24",
                            height = "auto",
                            text = string.format("%s: %d -> %d", dieType, from, to),
                        },
                        gui.Panel{
                            classes = "dvSetRemove",
                            click = function()
                                DiceVision.removeValueMapping(d, f)
                                rebuildMappingRows()
                            end,
                            gui.Label{
                                interactable = false,
                                width = "100%",
                                height = "100%",
                                halign = "center",
                                valign = "center",
                                color = "white",
                                fontSize = 11,
                                text = "x",
                            },
                        },
                    }
                end
            end
            if #rows == 0 then
                rows[1] = gui.Label{
                    classes = "dvSetInfo",
                    width = "100%",
                    height = "auto",
                    text = "(no mappings)",
                }
            end
            mappingRows.children = rows
        end

        -- Mirrors rebuildMappingRows for die-type mappings (e.g. Draw
        -- Steel's 20-sided d10s recognized as d20 -> treated as d10).
        rebuildTypeRows = function()
            local rows = {}
            for fromType, toType in pairs(DiceVision.rules.typeMappings) do
                local f = fromType
                rows[#rows + 1] = gui.Panel{
                    flow = "horizontal",
                    width = "100%",
                    height = "auto",
                    valign = "center",
                    gui.Label{
                        classes = "dvSetInfo",
                        width = "100%-24",
                        height = "auto",
                        text = string.format("%s -> %s", fromType, toType),
                    },
                    gui.Panel{
                        classes = "dvSetRemove",
                        click = function()
                            DiceVision.removeTypeMapping(f)
                            rebuildTypeRows()
                        end,
                        gui.Label{
                            interactable = false,
                            width = "100%",
                            height = "100%",
                            halign = "center",
                            valign = "center",
                            color = "white",
                            fontSize = 11,
                            text = "x",
                        },
                    },
                }
            end
            if #rows == 0 then
                rows[1] = gui.Label{
                    classes = "dvSetInfo",
                    width = "100%",
                    height = "auto",
                    text = "(no mappings)",
                }
            end
            typeRows.children = rows
        end

        statusInfo = gui.Label{ classes = "dvSetInfo", width = "100%", height = "auto", text = "" }
        testLine = gui.Label{ classes = "dvSetInfo", width = "100%", height = "auto", text = "" }

        clampLabel = gui.Label{
            interactable = false, width = 28, height = "auto",
            halign = "center", valign = "center", color = "white", fontSize = 11, text = "Off",
        }
        clampBtn = gui.Panel{
            classes = "dvSetBtn",
            click = function()
                DiceVision.setClampOutOfRange(not DiceVision.rules.clampOutOfRange)
                refreshClamp()
            end,
            clampLabel,
        }

        forcedLabel = gui.Label{
            interactable = false, width = 28, height = "auto",
            halign = "center", valign = "center", color = "white", fontSize = 11, text = "Off",
        }
        forcedBtn = gui.Panel{
            classes = "dvSetBtn",
            click = function()
                DiceVision.setUseForcedDice(not DiceVision.useForcedDice)
                refreshForcedDice()
            end,
            forcedLabel,
        }

        cardLabel = gui.Label{
            interactable = false, width = 28, height = "auto",
            halign = "center", valign = "center", color = "white", fontSize = 11, text = "Off",
        }
        cardBtn = gui.Panel{
            classes = "dvSetBtn",
            click = function()
                DiceVision.setForcedDiceChatCard(not DiceVision.forcedDiceChatCard)
                refreshForcedDice()
            end,
            cardLabel,
        }

        countInput = gui.Input{
            classes = "dvSetInput",
            width = 36,
            numeric = true,
            lineType = "SingleLine",
            text = "",
            change = function(element)
                local sel = DiceVision.rules.diceSelection
                if sel then
                    DiceVision.setDiceSelection(sel.keep, tonumber(element.text) or sel.count)
                    refreshKeep()
                end
            end,
        }
        local function selectKeep(mode)
            if mode == "auto" then
                DiceVision.setDiceSelection("auto")
            else
                DiceVision.setDiceSelection(mode, tonumber(countInput.text) or 1)
            end
            refreshKeep()
        end
        autoBtn = buildButton("Auto", function() selectKeep("auto") end)
        highBtn = buildButton("Highest", function() selectKeep("highest") end)
        lowBtn = buildButton("Lowest", function() selectKeep("lowest") end)

        addDie = gui.Input{ classes = "dvSetInput", width = 48, lineType = "SingleLine", placeholderText = "die", text = "" }
        addFrom = gui.Input{ classes = "dvSetInput", width = 36, numeric = true, lineType = "SingleLine", placeholderText = "from", text = "" }
        addTo = gui.Input{ classes = "dvSetInput", width = 36, numeric = true, lineType = "SingleLine", placeholderText = "to", text = "" }
        addStatus = gui.Label{ classes = "dvSetInfo", width = "100%", height = "auto", text = "" }
        local addBtn = buildButton("Add", function()
            -- The seam also chats a usage line on failure, but the chat window is
            -- a different surface; give popup-local feedback like the connect popup.
            if DiceVision.setValueMapping(addDie.text, addFrom.text, addTo.text) then
                addDie.text = ""
                addFrom.text = ""
                addTo.text = ""
                addStatus.text = ""
                rebuildMappingRows()
            else
                addStatus.text = "Enter a die and numeric from/to"
            end
        end)

        mappingRows = gui.Panel{ flow = "vertical", width = "100%", height = "auto" }

        typePanelLabel = gui.Label{
            interactable = false, width = 28, height = "auto",
            halign = "center", valign = "center", color = "white", fontSize = 11, text = "Off",
        }
        typePanelBtn = gui.Panel{
            classes = "dvSetBtn",
            click = function()
                DiceVision.setTypeMappingsOnPanel(not DiceVision.rules.typeMappingsOnPanel)
                refreshTypePanel()
            end,
            typePanelLabel,
        }

        typeFrom = gui.Input{ classes = "dvSetInput", width = 48, lineType = "SingleLine", placeholderText = "from", text = "" }
        typeTo = gui.Input{ classes = "dvSetInput", width = 48, lineType = "SingleLine", placeholderText = "to", text = "" }
        typeAddStatus = gui.Label{ classes = "dvSetInfo", width = "100%", height = "auto", text = "" }
        local typeAddBtn = buildButton("Add", function()
            -- Same popup-local feedback pattern as the value-mapping Add,
            -- but failure-specific: the seam returns a reason key.
            local ok, reason = DiceVision.setTypeMapping(typeFrom.text, typeTo.text)
            if ok then
                typeFrom.text = ""
                typeTo.text = ""
                typeAddStatus.text = ""
                rebuildTypeRows()
            elseif reason == "self" then
                typeAddStatus.text = "Mapping must change the die type"
            elseif reason == "target" then
                typeAddStatus.text = "Target must be d4/d6/d8/d10/d12/d20"
            else
                typeAddStatus.text = "Enter two die types (e.g. d20 d10)"
            end
        end)

        typeRows = gui.Panel{ flow = "vertical", width = "100%", height = "auto" }

        popupPanel = gui.Panel{
            styles = settingsPopupStyles,
            flow = "vertical",
            width = 250,
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
                if hostPanel then hostPanel.popup = nil end
            end,
            thinkTime = 0.25,
            think = function(element)
                refreshStatus()
            end,

            gui.Label{
                interactable = false, width = "auto", height = "auto",
                halign = "center", fontSize = 13, bold = true, color = "white",
                text = "DiceVision Settings", bmargin = 4,
            },

            -- Connection / diagnostics
            gui.Label{ classes = "dvSetHeader", text = "Connection" },
            statusInfo,
            gui.Panel{
                flow = "horizontal", width = "100%", height = "auto", tmargin = 4,
                buildButton("Disconnect", function() DiceVision.disconnect(); refreshStatus() end),
                buildButton("Refresh", function() DiceVision.refreshHooks(); refreshStatus() end),
                buildButton("Test", function(panel)
                    -- In-flight guard (like the connect popup): block concurrent
                    -- net.Get calls so repeated clicks do not spam chat or race
                    -- to write testLine out of order.
                    if testing then
                        return
                    end
                    testing = true
                    panel:SetClass("disabled", true)
                    testLine.text = "Testing..."
                    DiceVision.testConnection(function(success)
                        testing = false
                        if hostPanel and hostPanel.popup == popupPanel then
                            panel:SetClass("disabled", false)
                            testLine.text = success and "API reachable" or "API error"
                        end
                    end)
                end),
            },
            testLine,

            -- Forced dice (engine forcedDice support; needs a new Codex build)
            gui.Label{ classes = "dvSetHeader", text = "Forced Dice" },
            gui.Panel{
                flow = "horizontal", width = "100%", height = "auto", valign = "center",
                gui.Label{ classes = "dvSetInfo", width = "100%-60", height = "auto", text = "Use engine forcedDice" },
                forcedBtn,
            },
            gui.Panel{
                flow = "horizontal", width = "100%", height = "auto", valign = "center", tmargin = 4,
                gui.Label{ classes = "dvSetInfo", width = "100%-60", height = "auto", text = "DiceVision chat card" },
                cardBtn,
            },

            -- Dice rules
            gui.Label{ classes = "dvSetHeader", text = "Dice Rules" },
            gui.Panel{
                flow = "horizontal", width = "100%", height = "auto", valign = "center",
                gui.Label{ classes = "dvSetInfo", width = "100%-60", height = "auto", text = "Clamp out-of-range to 1" },
                clampBtn,
            },
            gui.Panel{
                flow = "horizontal", width = "100%", height = "auto", valign = "center", tmargin = 4,
                gui.Label{ classes = "dvSetInfo", width = 32, height = "auto", text = "Keep" },
                autoBtn, highBtn, lowBtn, countInput,
            },

            -- Value mappings
            gui.Label{ classes = "dvSetHeader", text = "Value Mappings" },
            mappingRows,
            gui.Panel{
                flow = "horizontal", width = "100%", height = "auto", valign = "center", tmargin = 4,
                addDie, addFrom, addTo, addBtn,
            },
            addStatus,

            -- Type mappings (e.g. Draw Steel 20-sided d10s recognized as d20)
            gui.Label{ classes = "dvSetHeader", text = "Type Mappings" },
            typeRows,
            gui.Panel{
                flow = "horizontal", width = "100%", height = "auto", valign = "center", tmargin = 4,
                typeFrom, typeTo, typeAddBtn,
            },
            typeAddStatus,
            gui.Panel{
                flow = "horizontal", width = "100%", height = "auto", valign = "center", tmargin = 4,
                gui.Label{ classes = "dvSetInfo", width = "100%-60", height = "auto", text = "Apply to panel rolls" },
                typePanelBtn,
            },

            gui.Panel{
                flow = "horizontal", width = "100%", height = "auto", tmargin = 4,
                buildButton("Reset defaults", function()
                    DiceVision.clearRules(false); refreshAllRules()
                end),
                buildButton("Clear all", function()
                    DiceVision.clearRules(true); refreshAllRules()
                end),
            },
        }

        -- Initial paint from current state.
        refreshStatus()
        refreshClamp()
        refreshForcedDice()
        refreshTypePanel()
        refreshKeep()
        if DiceVision.rules.diceSelection then
            countInput.text = tostring(DiceVision.rules.diceSelection.count)
        end
        rebuildMappingRows()
        rebuildTypeRows()

        return popupPanel
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
                -- Connect is driven from the toggle button below; the dice
                -- image just rolls. When disconnected it points the user there.
                chat.Send("[DiceVision] Not connected. Click Connect... to start.")
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
            text = "Connect DiceVision, or toggle roll interception on/off",
            valign = "top",
        },

        click = function(panel)
            if not DiceVision.connected then
                -- Disconnected: this button is the Connect call-to-action.
                togglePopup(panel, CreateConnectPopup)
                return
            end
            -- Connected: the toggle contract (compute opposite mode, pass
            -- verbose on replace, emit confirmation) lives in
            -- DiceVision._panelToggle so it can be exercised directly by tests.
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

        -- Floating gear (top-right) opening the settings popup. floating so it
        -- does not consume any of the fixed 100px row height.
        gui.Panel{
            floating = true,
            halign = "right",
            valign = "top",
            width = 18,
            height = 18,
            tmargin = 2,
            rmargin = 8,
            bgimage = "panels/hud/gear.png",
            bgcolor = "white",
            hover = gui.Tooltip{
                text = "DiceVision settings",
                valign = "bottom",
            },
            styles = {
                { classes = "hover", scale = 1.15, brightness = 1.2 },
            },
            click = function(panel)
                togglePopup(panel, CreateSettingsPopup)
            end,
        },
    }

    updateState()
    return resultPanel
end

print("DV: DVDicePanel loaded")
