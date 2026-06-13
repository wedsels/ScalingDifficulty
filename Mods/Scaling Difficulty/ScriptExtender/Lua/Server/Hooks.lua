--- @param _V _V
--- @param _F _F
--- @param _E Entity
return function( _V, _F, _E )
    local Entities = {}
    Ext.Entity.OnCreateDeferred( "Active", function( ent ) Entities[ #Entities + 1 ] = ent end )

    Ext.Events.GameStateChanged:Subscribe(
        function( e )
            if e.FromState == "Running" and e.ToState == "Save" then _E.Update( true ) return end
            if e.FromState == "Save" and e.ToState == "Running" then _E.Update() return end

            if e.FromState ~= "LoadLevel" or e.ToState ~= "Sync" then return end

            local modvar = Ext.Vars.GetModVariables( ModuleUUID )
            if not modvar.Seed then
                modvar.Seed = math.random( math.maxinteger )
            end
            _V.Seed = modvar.Seed

            local Settings = _F.DefaultBlueprint()

            local function SetSettings()
                for npc,_ in pairs( _V.NPC ) do
                    _V.Hub[ npc ] = _V.Hub[ npc ] or {}
                    for _,setting in ipairs( _V.Settings ) do
                        _V.Hub[ npc ][ setting ] = _V.Hub[ npc ][ setting ] or {}

                        for _,stat in ipairs( _V[ setting ] or _V.Stats ) do
                            _V.Hub[ npc ][ setting ][ stat ] = Settings[ setting .. npc .. stat ]
                        end
                    end
                end
            end

            if MCM then
                for setting,_ in pairs( Settings ) do
                    local val = MCM.Get( setting )
                    if val ~= nil then
                        Settings[ setting ] = val
                    end
                end

                _F.Blacklist()
            end

            SetSettings()

            for _,p in pairs( Osi.DB_Players:Get( nil ) ) do
                local level = Osi.GetLevel( p[ 1 ] )
                if level > _V.PartyLevel then
                    _V.PartyLevel = level
                end
            end

            Ext.Events.Tick:Subscribe(
                function()
                    if #Entities == 0 then return end

                    for _,i in ipairs( Entities ) do
                        if i then
                            _E.AddNPC( i )
                        end
                    end
                    Entities = {}
                end
            )

            Ext.Entity.OnCreateDeferred(
                "LevelChanged",
                function( ent, _, index )
                    local uuid = _F.UUID( ent )
                    if not uuid then return end

                    local l = ent.LevelChanged
                    if l.PreviousLevel == _V.PartyLevel and l.NewLevel > _V.PartyLevel and Osi.DB_Players:Get( uuid )[ 1 ] then
                        _V.PartyLevel = l.NewLevel
                        _E.Update()
                    end
                end
            )

            local function Dispatch( func, ent, index )
                if not ent then return end

                local uuid = _F.UUID( ent )
                if not uuid then return end

                local entity = _V.Entities[ uuid ]
                if not entity then return end

                entity[ func ]( entity, index )
            end

            Ext.Entity.OnChange( "Stats", function( ent, _, index ) Dispatch( "SetAbilities", ent, index ) end )
            Ext.Entity.OnChange( "Health", function( ent, _, index ) Dispatch( "SetHealth", ent, index ) end )
            Ext.Entity.OnChange( "EocLevel", function( ent, _, index ) Dispatch( "SetLevel", ent ) end )
            Ext.Entity.OnChange( "Resistances", function( ent, _, index ) Dispatch( "SetAC", ent, index ) end )

            Ext.Entity.OnChange(
                "TurnBased",
                function( ent, _, index )
                    if ent.TurnBased.ActedThisRoundInCombat or not ent.TurnBased.CanActInCombat then return end

                    local uuid = _F.UUID( ent )
                    if not uuid then return end

                    local entity = _V.Entities[ uuid ]
                    if not entity then return end

                    local old = entity.Type
                    entity:Archetype()

                    if old ~= entity.Type then
                        entity:Recalculate()
                    end
                end
            )
        end
    )
end