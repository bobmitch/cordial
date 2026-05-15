#include "LuaHost.h"

#include "BinaryData.h"

LuaHost::LuaHost()
{
    lua.open_libraries(sol::lib::base,
                       sol::lib::math,
                       sol::lib::string,
                       sol::lib::table);

    const auto* src  = BinaryData::host_vst_lua;
    const auto  size = static_cast<std::size_t>(BinaryData::host_vst_luaSize);

    auto result = lua.safe_script(std::string_view(src, size),
                                  sol::script_pass_on_error);

    if (! result.valid())
    {
        sol::error err = result;
        juce::Logger::writeToLog(juce::String("Cordial Lua load failed: ") + err.what());
        return;
    }

    sol::object returned = result;
    if (returned.get_type() != sol::type::table)
    {
        juce::Logger::writeToLog("Cordial Lua: host_vst.lua did not return a table");
        return;
    }

    hostModule = returned.as<sol::table>();
    loaded     = true;
}

std::optional<LuaHost::Chord> LuaHost::getPhase1Chord()
{
    if (! loaded)
        return std::nullopt;

    sol::protected_function fn = hostModule["phase1_chord"];
    if (! fn.valid())
        return std::nullopt;

    sol::protected_function_result res = fn();
    if (! res.valid())
    {
        sol::error err = res;
        juce::Logger::writeToLog(juce::String("phase1_chord error: ") + err.what());
        return std::nullopt;
    }

    sol::table t = res;
    Chord out;
    sol::table notes = t["notes"];
    // ipairs-style iteration: range-based for on sol::table uses pairs()
    // semantics, which is not guaranteed to enumerate the array part of a
    // Lua sequence in sol2 v3. Walking integer indices until the first
    // missing slot is the canonical idiom for {a, b, c}-style tables.
    for (std::size_t i = 1; ; ++i)
    {
        sol::optional<int> v = notes[i];
        if (! v)
            break;
        out.notes.push_back (*v);
    }
    out.velocity    = t.get_or("velocity", 100);
    out.lengthBeats = t.get_or("length_beats", 4.0);
    return out;
}

juce::String LuaHost::ping()
{
    if (! loaded)
        return {};

    sol::protected_function fn = hostModule["ping"];
    if (! fn.valid())
        return {};

    sol::protected_function_result res = fn();
    if (! res.valid())
        return {};

    return juce::String(res.get<std::string>());
}
