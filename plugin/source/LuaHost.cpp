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

std::vector<LuaHost::MidiEvent> LuaHost::generate(const Params& params)
{
    std::vector<MidiEvent> out;
    if (! loaded) return out;

    sol::protected_function fn = hostModule["generate"];
    if (! fn.valid())
    {
        juce::Logger::writeToLog("Cordial: generate() not found in host_vst.lua");
        return out;
    }

    // Build the Lua params table. Field names mirror core.chord.build_progression
    // so the Lua side can pass them straight through without renaming.
    sol::table p = lua.create_table();
    p["mode"]         = params.mode;
    p["root_idx"]     = params.rootIdx;
    p["octave"]       = params.octave;
    p["timesig_num"]  = params.timesigNum;
    p["smart_voicing"] = params.smartVoicing;

    sol::table degs = lua.create_table();
    for (std::size_t i = 0; i < params.degrees.size(); ++i)
        degs[static_cast<int>(i + 1)] = params.degrees[i];
    p["degrees"] = degs;

    sol::protected_function_result res = fn(p);
    if (! res.valid())
    {
        sol::error err = res;
        juce::Logger::writeToLog("Cordial generate() error: " + juce::String(err.what()));
        return out;
    }

    // Parse the returned sequence of {pos_beats, note, vel, dur_beats, channel}.
    sol::table events = res;
    for (std::size_t i = 1; ; ++i)
    {
        sol::optional<sol::table> ev = events[i];
        if (! ev) break;

        MidiEvent e;
        e.posBeats  = ev->get_or("pos_beats",  0.0);
        e.note      = ev->get_or("note",        60);
        e.velocity  = ev->get_or("vel",        100);
        e.durBeats  = ev->get_or("dur_beats",  4.0);
        e.channel   = ev->get_or("channel",     1);
        out.push_back(e);
    }
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
