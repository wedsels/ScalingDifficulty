--- @diagnostic disable: missing-fields

local settings = {
    Server = true,
    Client = false,
    WriteableOnServer = true,
    WriteableOnClient = false,
    Persistent = true,
    SyncToClient = false,
    SyncToServer = false,
    SyncOnTick = true,
    SyncOnWrite = false,
    DontCache = false,
}

Ext.Vars.RegisterModVariable( ModuleUUID, "Seed", settings )
Ext.Vars.RegisterUserVariable( "HealthCache", settings )
Ext.Vars.RegisterUserVariable( "SpellCache", settings )
Ext.Vars.RegisterUserVariable( "NameCache", settings )

--- @class _V
local _V = {}

_V.Key = "Scaling Difficulty"
_V.Seed = 0

_V.PartyLevel = 0

--- @type Stats
_V.Stats = {}
--- @class Stats
--- @field Enabled boolean
--- @field HP number
--- @field PercentHP number
--- @field AC number
--- @field Attack number
--- @field DamageBonus number
--- @field Initiative number
--- @field Physical number
--- @field Casting number
--- @field Strength number
--- @field Dexterity number
--- @field Constitution number
--- @field Intelligence number
--- @field Wisdom number
--- @field Charisma number
--- @field Experience number
--- @field PercentExperience number
--- @field Size number

--- @type Resource
_V.Resource = {}
--- @class Resource
--- @field Enabled boolean
--- @field SpellSlotLevel1 string
--- @field SpellSlotLevel2 string
--- @field SpellSlotLevel3 string
--- @field SpellSlotLevel4 string
--- @field SpellSlotLevel5 string
--- @field SpellSlotLevel6 string
--- @field SpellSlotLevel7 string
--- @field SpellSlotLevel8 string
--- @field SpellSlotLevel9 string
--- @field Movement string
--- @field ActionPoint string
--- @field BonusActionPoint string
--- @field ReactionActionPoint string
--- @field Rage string
--- @field KiPoint string
--- @field WildShape string
--- @field ChannelOath string
--- @field SorceryPoint string
--- @field SuperiorityDie string
--- @field ChannelDivinity string
--- @field BardicInspiration string

--- @type General
_V.General = {}
--- @class General
--- @field Enabled boolean
--- @field MaxLevel number
--- @field LevelBonus number
--- @field Downscaling boolean
--- @field ExperienceLevel boolean
--- @field Spells number

--- @type Settings
_V.Settings = {}
--- @class Settings
--- @field General General
--- @field Bonus Stats
--- @field Leveling Stats
--- @field Variation Stats
--- @field Resource Resource

--- @type table< string, Settings >
_V.Hub = {}
_V.NPC = {
    Hostile = true,
    Ally = true,
    Summon = true,
    Elite = true,
    Player = true
}

--- @class Health
--- @field Hp number
--- @field MaxHp number
--- @field Percent number
--- @field Transformed boolean
--- @field TransformedHp number
--- @field TransformedMaxHp number
--- @field TransformedPercent number

--- @class Modifiers
--- @field Original Stats
--- @field Current Stats

--- @class Entity
--- @field Name string
--- @field UUID string
--- @field Instance any
--- @field Disabled boolean
--- @field Faction string
--- @field Scaled boolean
--- @field Type string
--- @field Hub Settings
--- @field LevelBase number
--- @field LevelChange number
--- @field Experience table< number >
--- @field Physical string
--- @field Casting string
--- @field Stats Stats
--- @field Skills table< number >
--- @field Resource Resource
--- @field OldStats Stats
--- @field OldSkills table< number >
--- @field OldResource Resource
--- @field OldSpells number
--- @field OldBlacklist table< string, boolean >
--- @field OldSize number
--- @field OldWeight number
--- @field Health Health
--- @field Modifiers Modifiers
--- @field SpellCache table< string >

--- @type table< string, Entity >
_V.Entities = {}

--- @type table< string, boolean >
_V.Blacklist = {}

--- @type table< string, boolean >
_V.SpellBlacklist = {}

_V.Abilities = {
    Strength = 2,
    Dexterity = 3,
    Constitution = 4,
    Intelligence = 5,
    Wisdom = 6,
    Charisma = 7
}

_V.AbilitiesReverse = {}
for s,v in pairs( _V.Abilities ) do
    _V.AbilitiesReverse[ v ] = s
end

_V.AbilitiesMatch = {
    _V.Abilities.Charisma,
    _V.Abilities.Charisma,
    _V.Abilities.Charisma,
    _V.Abilities.Charisma,
    _V.Abilities.Dexterity,
    _V.Abilities.Dexterity,
    _V.Abilities.Dexterity,
    _V.Abilities.Intelligence,
    _V.Abilities.Intelligence,
    _V.Abilities.Intelligence,
    _V.Abilities.Intelligence,
    _V.Abilities.Intelligence,
    _V.Abilities.Strength,
    _V.Abilities.Wisdom,
    _V.Abilities.Wisdom,
    _V.Abilities.Wisdom,
    _V.Abilities.Wisdom,
    _V.Abilities.Wisdom
}

_V.Boosts = {
    Resource = "ActionResource( %s, %d, %d )",
    RollBonus = "RollBonus( %s, %d )",
    DamageBonus = "DamageBonus( %d )",
    Size = "ScaleMultiplier( %f );CarryCapacityMultiplier( %f );Weight( %d )"
}

local class = {}
for _,type in pairs( Ext.StaticData.GetAll( "ClassDescription" ) ) do
    local data = Ext.StaticData.Get( type, "ClassDescription" )
    if data then
        local list = Ext.StaticData.Get( data.SpellList, "SpellList" )
        if list then
            local s = tostring( data.SpellCastingAbility )
            class[ s ] = class[ s ] or {}
            for _,i in pairs( list.Spells ) do
                class[ s ][ i ] = true
            end
        end
    end
end

--- @type table< string, table< string > >
_V.Classes = {}
for k,v in pairs( class ) do
    _V.Classes[ k ] = {}
    for i,_ in pairs( v ) do
        _V.Classes[ k ][ # _V.Classes[ k ] + 1 ] = i
    end
end

--- @type table< string, table< integer > >
_V.Experience = {}
for _,type in pairs( Ext.StaticData.GetAll( "ExperienceReward" ) ) do
    local data = Ext.StaticData.Get( type, "ExperienceReward" )
    if data then
        _V.Experience[ type ] = {}
        for i = 1, 12 do
            _V.Experience[ type ][ i ] = data.PerLevelRewards[ i ]
        end
    end
end

_V.JsonBlueprint = Ext.Json.Parse( Ext.IO.LoadFile( "Mods/Scaling Difficulty/MCM_blueprint.json", "data" ) )

--- @type table< string, table< string > >
_V.SpellNames = {}
for _,spell in ipairs( Ext.Stats.GetStats( "SpellData" ) ) do
    local data = Ext.Stats.Get( spell )
    local name = Ext.Loca.GetTranslatedString( data.DisplayName ):gsub( "[%s%p]", "" ):lower()
    _V.SpellNames[ name ] = _V.SpellNames[ name ] or {}
    table.insert( _V.SpellNames[ name ], spell )
end

local class
for line in Ext.IO.LoadFile( "Mods/Scaling Difficulty/ScriptExtender/Lua/Server/Variables.lua", "data" ):gmatch( "[^\r\n]+" ) do
    if class then
        local field = line:match( "^%s*---%s*@field%s+([%w_]+)" )
        if field then
            table.insert( _V[ class ], field )
        else
            class = nil
        end
    elseif line:find( "--- @class" ) then
        local l = line:match( "^%s*---%s*@class%s+([%w_]+)" )
        if _V[ l ] then
            class = l
        end
    end
end

return _V