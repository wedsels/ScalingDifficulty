local _V = require( "Server/Variables" )
local _F = require( "Server/Functions" )( _V )
local _E = require( "Server/Entity" )( _V, _F )
local _H = require( "Server/Hooks" )( _V, _F, _E )
local _J = require( "Server/Json" )

Ext.RegisterConsoleCommand( "BPSD", function() print( _J( _V ) ) end )
Ext.RegisterConsoleCommand( "SSD", function() print( _V.Seed ) end )

if MCM then
    local function split( str )
        local ret = {}

        for s in str:gmatch( "[A-Z][^A-Z]*" ) do
            if not ret[ 3 ] then
                table.insert( ret, s )
            else
                ret[ 3 ] = ret[ 3 ] .. s
            end
        end

        return ret
    end

    Ext.ModEvents.BG3MCM.MCM_Setting_Saved:Subscribe(
        function( payload )
            if not payload or not payload.settingId or payload.modUUID ~= ModuleUUID or payload.settingId == "NPC" or payload.settingId == "Page" then
                return
            end

            if payload.settingId == "Seed" then
                local modvar = Ext.Vars.GetModVariables( ModuleUUID )
                modvar.Seed = math.random( math.maxinteger )
                _V.Seed = modvar.Seed

                _E.Update()
            elseif payload.settingId == "RefreshHealth" then
                for _,ent in pairs( Ext.Entity.GetAllEntities() ) do
                    local uuid = _F.UUID( ent )
                    if uuid then
                        Osi.AddBoosts( uuid, "IncreaseMaxHP( 0 )", _V.Key, "" )
                        Ext.Timer.WaitFor( 500, function() Osi.RemoveBoosts( uuid, "IncreaseMaxHP( 0 )", 0, _V.Key, "" ) end )
                    end
                end
            elseif payload.settingId:find( "Blacklist" ) then
                _F.Blacklist()
                _E.Update()
            elseif payload.value ~= nil then
                local s = split( payload.settingId )

                if _V.Hub[ s[ 2 ] ] and _V.Hub[ s[ 2 ] ][ s[ 1 ] ] then
                    _V.Hub[ s[ 2 ] ][ s[ 1 ] ][ s[ 3 ] ] = payload.value
                end

                for _,i in pairs( _V.Entities ) do
                    if i.Type == s[ 2 ] then
                        i:Recalculate()
                    end
                end
            end
        end
    )
end