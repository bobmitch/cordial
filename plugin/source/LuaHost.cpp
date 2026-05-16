#include "LuaHost.h"

#include "BinaryData.h"

namespace
{
    struct PreloadEntry { const char* requireName; const char* src; int size; };

    const PreloadEntry kCoreModules[] = {
        { "core",              BinaryData::init_lua,          BinaryData::init_luaSize          },
        { "core.theory",       BinaryData::theory_lua,        BinaryData::theory_luaSize        },
        { "core.progressions", BinaryData::progressions_lua,  BinaryData::progressions_luaSize  },
        { "core.rng",          BinaryData::rng_lua,           BinaryData::rng_luaSize           },
        { "core.chord",        BinaryData::chord_lua,         BinaryData::chord_luaSize         },
        { "core.arp",          BinaryData::arp_lua,           BinaryData::arp_luaSize           },
        { "core.voicing",      BinaryData::voicing_lua,       BinaryData::voicing_luaSize       },
        { "core.bass",         BinaryData::bass_lua,          BinaryData::bass_luaSize          },
        { "core.melody",       BinaryData::melody_lua,        BinaryData::melody_luaSize        },
    };
}

LuaHost::LuaHost()
{
    lua.open_libraries (sol::lib::base,
                        sol::lib::math,
                        sol::lib::string,
                        sol::lib::table,
                        sol::lib::package);

    sol::table preload = lua["package"]["preload"];
    for (const auto& m : kCoreModules)
    {
        std::string src  (m.src, static_cast<std::size_t> (m.size));
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
    const auto  size = static_cast<std::size_t> (BinaryData::host_vst_luaSize);

    auto result = lua.safe_script (std::string_view (src, size),
                                   sol::script_pass_on_error);
    if (! result.valid())
    {
        sol::error err = result;
        juce::Logger::writeToLog ("Cordial Lua load failed: " + juce::String (err.what()));
        return;
    }

    sol::object returned = result;
    if (returned.get_type() != sol::type::table)
    {
        juce::Logger::writeToLog ("Cordial Lua: host_vst.lua did not return a table");
        return;
    }

    hostModule = returned.as<sol::table>();
    loaded     = true;
}

std::vector<LuaHost::PresetInfo> LuaHost::getPresets()
{
    std::vector<PresetInfo> out;
    if (! loaded) return out;

    sol::protected_function fn = hostModule["get_presets"];
    if (! fn.valid()) return out;

    sol::protected_function_result res = fn();
    if (! res.valid()) return out;

    sol::table list = res;
    for (std::size_t i = 1; ; ++i)
    {
        sol::optional<sol::table> entry = list[i];
        if (! entry) break;
        PresetInfo info;
        info.name     = juce::String (entry->get_or<std::string> ("name", ""));
        info.category = juce::String (entry->get_or<std::string> ("cat",  ""));
        out.push_back (std::move (info));
    }
    return out;
}

std::vector<LuaHost::MidiEvent> LuaHost::generate (const Params& params)
{
    std::vector<MidiEvent> out;
    if (! loaded) return out;

    sol::protected_function fn = hostModule["generate"];
    if (! fn.valid())
    {
        juce::Logger::writeToLog ("Cordial: generate() not found in host_vst.lua");
        return out;
    }

    sol::table p = lua.create_table();
    p["mode"]            = params.mode;
    p["root_idx"]        = params.rootIdx;
    p["octave"]          = params.octave;
    p["timesig_num"]     = params.timesigNum;
    p["smart_voicing"]   = params.smartVoicing;
    p["progression_idx"] = params.progressionIdx;
    p["seed"]            = params.seed;

    // Phase 6: layer enable flags + arp parameters
    p["chord_enabled"]   = params.chordEnabled;
    p["arp_enabled"]     = params.arpEnabled;
    p["arp_pattern"]     = params.arpPattern;
    p["arp_rate_beats"]  = params.arpRateBeats;
    p["arp_octaves"]     = params.arpOctaves;
    p["arp_rigidity"]    = params.arpRigidity;
    p["mel_enabled"]     = params.melEnabled;

    sol::table degs = lua.create_table();
    for (std::size_t i = 0; i < params.degrees.size(); ++i)
        degs[static_cast<int> (i + 1)] = params.degrees[i];
    p["degrees"] = degs;

    sol::protected_function_result res = fn (p);
    if (! res.valid())
    {
        sol::error err = res;
        juce::Logger::writeToLog ("Cordial generate() error: " + juce::String (err.what()));
        return out;
    }

    sol::table events = res;
    for (std::size_t i = 1; ; ++i)
    {
        sol::optional<sol::table> ev = events[i];
        if (! ev) break;

        MidiEvent e;
        e.posBeats = ev->get_or ("pos_beats", 0.0);
        e.note     = ev->get_or ("note",       60);
        e.velocity = ev->get_or ("vel",       100);
        e.durBeats = ev->get_or ("dur_beats",  4.0);
        e.channel  = ev->get_or ("channel",     1);
        out.push_back (e);
    }
    return out;
}

juce::String LuaHost::ping()
{
    if (! loaded) return {};

    sol::protected_function fn = hostModule["ping"];
    if (! fn.valid()) return {};

    sol::protected_function_result res = fn();
    if (! res.valid()) return {};

    return juce::String (res.get<std::string>());
}
