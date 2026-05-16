#include "LuaHost.h"

#include "BinaryData.h"

namespace
{
    // One entry per Lua module embedded as JUCE BinaryData. The `require`
    // name is what host_vst.lua (and any core module that does
    // `require 'core.X'`) asks for; the src/size point at the embedded
    // source bytes. Order doesn't matter — preload is lazy.
    struct PreloadEntry { const char* requireName; const char* src; int size; };

    const PreloadEntry kCoreModules[] = {
        { "core",             BinaryData::init_lua,         BinaryData::init_luaSize         },
        { "core.theory",      BinaryData::theory_lua,       BinaryData::theory_luaSize       },
        { "core.progressions",BinaryData::progressions_lua, BinaryData::progressions_luaSize },
        { "core.rng",         BinaryData::rng_lua,          BinaryData::rng_luaSize          },
        { "core.chord",       BinaryData::chord_lua,        BinaryData::chord_luaSize        },
        { "core.arp",         BinaryData::arp_lua,          BinaryData::arp_luaSize          },
        { "core.voicing",     BinaryData::voicing_lua,      BinaryData::voicing_luaSize      },
        { "core.bass",        BinaryData::bass_lua,         BinaryData::bass_luaSize         },
        { "core.melody",      BinaryData::melody_lua,       BinaryData::melody_luaSize       },
    };
}

LuaHost::LuaHost()
{
    lua.open_libraries(sol::lib::base,
                       sol::lib::math,
                       sol::lib::string,
                       sol::lib::table,
                       sol::lib::package);  // for package.preload[]

    // Register every core module's source with package.preload BEFORE
    // loading host_vst.lua. The closure runs on first require for that
    // module name; the result (the `return M` value) is cached by Lua
    // for subsequent requires.
    sol::table preload = lua["package"]["preload"];
    for (const auto& m : kCoreModules)
    {
        std::string src (m.src, static_cast<std::size_t>(m.size));
        std::string name = m.requireName;
        preload[name] = [src, name](sol::this_state s) -> sol::object {
            sol::state_view lv (s);
            auto r = lv.safe_script (src, sol::script_pass_on_error);
            if (! r.valid())
            {
                sol::error err = r;
                juce::Logger::writeToLog ("Cordial preload of " + juce::String (name)
                                          + " failed: " + err.what());
                return sol::lua_nil;
            }
            return r;
        };
    }

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
