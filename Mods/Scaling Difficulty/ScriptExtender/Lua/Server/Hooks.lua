--- @param _V _V
--- @param _F _F
--- @param _E Entity
return function( _V, _F, _E )
    Ext.Events.GameStateChanged:Subscribe(
        function( e )
            if e.FromState == "Running" and e.ToState == "UnloadLevel" then for _,entity in pairs( _V.Entities ) do entity:Destroy( true ) end return end

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

                _V.Debug = MCM.Get( "Debug" )
            end

            SetSettings()

            for _,p in pairs( Osi.DB_Players:Get( nil ) ) do
                local level = Osi.GetLevel( p[ 1 ] )
                if level > _V.PartyLevel then
                    _V.PartyLevel = level
                end
            end

            Ext.Entity.OnCreateDeferred( "Active", function( ent ) _E.AddNPC( ent ) end )
        end
    )
end