// Small Godot C ABI boundary. FMOD event policy stays in GDScript; this layer
// owns native lifetimes and exposes only bounded operations, never raw pointers.
// The shipped FMODUnity.dll is the authority for these C signatures and enums.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include "gdextension_interface.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <unordered_map>

namespace gd {
GDExtensionInterfaceGetProcAddress api;
GDExtensionClassLibraryPtr library;
template<class T> T get(const char *name) {
    auto function = api(name);
    if (!function) throw std::runtime_error(std::string("Godot API missing: ") + name);
    return reinterpret_cast<T>(function);
}
// Both opaque types are one pointer on the supported 64-bit ABI. No Variant
// storage is invented: Godot allocates method arguments and the return Variant.
struct Name {
    alignas(8) std::array<unsigned char, 8> data;
    explicit Name(const char *text) { get<GDExtensionInterfaceStringNameNewWithUtf8Chars>("string_name_new_with_utf8_chars")(data.data(), text); }
    ~Name() { get<GDExtensionInterfaceVariantGetPtrDestructor>("variant_get_ptr_destructor")(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(data.data()); }
};
struct String {
    alignas(8) std::array<unsigned char, 8> data;
    explicit String(const char *text) { get<GDExtensionInterfaceStringNewWithUtf8Chars>("string_new_with_utf8_chars")(data.data(), text); }
    explicit String(GDExtensionConstVariantPtr variant) {
        get<GDExtensionInterfaceGetVariantToTypeConstructor>("get_variant_to_type_constructor")(GDEXTENSION_VARIANT_TYPE_STRING)(data.data(), const_cast<void *>(variant));
    }
    ~String() { get<GDExtensionInterfaceVariantGetPtrDestructor>("variant_get_ptr_destructor")(GDEXTENSION_VARIANT_TYPE_STRING)(data.data()); }
    std::string utf8() const {
        auto convert = get<GDExtensionInterfaceStringToUtf8Chars>("string_to_utf8_chars");
        auto length = convert(data.data(), nullptr, 0);
        std::string result(static_cast<size_t>(length), '\0');
        convert(data.data(), result.data(), length);
        return result;
    }
};
}

struct FmodFailure { int code; };
struct NativeRuntime {
    HMODULE module = nullptr;
    void *system = nullptr;
    void *core = nullptr;
    void *master = nullptr;
    std::unordered_map<uint64_t, void *> events;
    uint64_t next_handle = 1;
    std::string output_file; // Keep WAVWRITER's extradriverdata alive.

    template<class... Args> int call(const char *name, Args... args) {
        if (!module) return 10001;
        auto symbol = GetProcAddress(module, name);
        if (!symbol) return 10002;
        return reinterpret_cast<int (__cdecl *)(Args...)>(symbol)(args...);
    }
    static void check(int result) { if (result != 0) throw FmodFailure{result}; }
    void close() noexcept {
        if (system) {
            call("FMOD_Studio_System_Release", system);
            system = core = master = nullptr;
        }
        events.clear();
        if (module) { FreeLibrary(module); module = nullptr; }
    }
    ~NativeRuntime() { close(); }

    static std::array<unsigned char, 16> guid(const std::string &text) {
        unsigned int a, b, c, d[8];
        int count = sscanf_s(text.c_str(), "%8x-%4x-%4x-%2x%2x-%2x%2x%2x%2x%2x%2x", &a, &b, &c,
            &d[0], &d[1], &d[2], &d[3], &d[4], &d[5], &d[6], &d[7]);
        if (count != 11 || text.size() != 36) throw FmodFailure{10003};
        std::array<unsigned char, 16> out{};
        for (int i = 0; i < 4; ++i) out[i] = static_cast<unsigned char>(a >> (i * 8));
        out[4] = static_cast<unsigned char>(b); out[5] = static_cast<unsigned char>(b >> 8);
        out[6] = static_cast<unsigned char>(c); out[7] = static_cast<unsigned char>(c >> 8);
        for (int i = 0; i < 8; ++i) out[i + 8] = static_cast<unsigned char>(d[i]);
        return out;
    }

    std::string run(const std::string &command, const std::string &a, const std::string &b, const std::string &c) {
        if (command == "close") { close(); return "0"; }
        if (command == "open") {
            close();
            auto path = std::filesystem::u8path(a) / "fmodstudio.dll";
            module = LoadLibraryExW(path.c_str(), nullptr, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
            if (!module) throw FmodFailure{10004};
            check(call("FMOD_Studio_System_Create", &system, 131617u)); // 2.02.33
            check(call("FMOD_Studio_System_GetCoreSystem", system, &core));
            int mode = c == "realtime" ? 0 : (c == "silent" ? 4 : 5);
            output_file = mode == 5 ? c : "";
            check(call("FMOD_System_SetOutput", core, mode));
            check(call("FMOD_System_SetDSPBufferSize", core, 512u, 2));
            check(call("FMOD_System_SetSoftwareFormat", core, 48000, 3, 0));
            // Offline DSP can outrun the disk worker. Pull streaming and Studio
            // loading from Update as well, so WAV output cannot silently starve.
            unsigned int studio_flags = mode == 0 ? 4u : (4u | 16u);
            unsigned int core_flags = mode == 0 ? 0u : (1u | 2u); // STREAM + MIX_FROM_UPDATE
            check(call("FMOD_Studio_System_Initialize", system, 256, studio_flags, core_flags,
                output_file.empty() ? nullptr : const_cast<char *>(output_file.c_str())));
            for (const char *bank : {"Master", "Master.strings", "AMB", "BGM", "Snapshot"}) {
                void *handle = nullptr;
                auto file = (std::filesystem::u8path(b) / (std::string(bank) + ".bank")).u8string();
                check(call("FMOD_Studio_System_LoadBankFile", system, file.c_str(), 0u, &handle));
            }
            check(call("FMOD_System_GetMasterChannelGroup", core, &master));
            return "0";
        }
        if (!system) throw FmodFailure{10005};
        if (command == "update") { check(call("FMOD_Studio_System_Update", system)); return "0"; }
        if (command == "clock") {
            uint64_t clock = 0, parent = 0;
            check(call("FMOD_ChannelGroup_GetDSPClock", master, &clock, &parent));
            return std::to_string(clock);
        }
        if (command == "create") {
            auto id = guid(a); void *description = nullptr, *instance = nullptr;
            check(call("FMOD_Studio_System_GetEventByID", system, id.data(), &description));
            check(call("FMOD_Studio_EventDescription_LoadSampleData", description));
            check(call("FMOD_Studio_System_FlushSampleLoading", system));
            check(call("FMOD_Studio_EventDescription_CreateInstance", description, &instance));
            auto handle = next_handle++;
            events.emplace(handle, instance);
            return std::to_string(handle);
        }
        if (command == "volume") {
            void *bus = nullptr;
            check(call("FMOD_Studio_System_GetBus", system, a.c_str(), &bus));
            check(call("FMOD_Studio_Bus_SetVolume", bus, std::stof(b)));
            return "0";
        }
        if (command == "count") return std::to_string(events.size());
        auto found = events.find(std::stoull(a));
        if (found == events.end()) throw FmodFailure{10006};
        void *event = found->second;
        if (command == "start") check(call("FMOD_Studio_EventInstance_Start", event));
        else if (command == "stop_release") {
            check(call("FMOD_Studio_EventInstance_Stop", event, 0)); // ALLOWFADEOUT
            check(call("FMOD_Studio_EventInstance_Release", event));
            events.erase(found);
        } else if (command == "set") check(call("FMOD_Studio_EventInstance_SetParameterByName", event, b.c_str(), std::stof(c), 0));
        else if (command == "get") {
            float requested = 0, final = 0;
            check(call("FMOD_Studio_EventInstance_GetParameterByName", event, b.c_str(), &requested, &final));
            return std::to_string(requested) + "," + std::to_string(final);
        } else if (command == "state") {
            int state = 0;
            check(call("FMOD_Studio_EventInstance_GetPlaybackState", event, &state));
            return std::to_string(state);
        } else if (command == "position") {
            int time = 0;
            check(call("FMOD_Studio_EventInstance_GetTimelinePosition", event, &time));
            return std::to_string(time);
        } else if (command == "pause") check(call("FMOD_Studio_EventInstance_SetPaused", event, b == "true" ? 1 : 0));
        else throw FmodFailure{10007};
        return "0";
    }
};

static void invoke(void *, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args,
    GDExtensionInt count, GDExtensionVariantPtr out, GDExtensionCallError *error) {
    error->error = GDEXTENSION_CALL_OK;
    std::string result;
    try {
        if (count != 4) throw FmodFailure{10008};
        for (int i = 0; i < 4; ++i)
            if (gd::get<GDExtensionInterfaceVariantGetType>("variant_get_type")(args[i]) != GDEXTENSION_VARIANT_TYPE_STRING) throw FmodFailure{10009};
        auto value = static_cast<NativeRuntime *>(instance)->run(gd::String(args[0]).utf8(), gd::String(args[1]).utf8(), gd::String(args[2]).utf8(), gd::String(args[3]).utf8());
        result = "0:" + value;
    } catch (const FmodFailure &failure) { result = std::to_string(failure.code) + ":"; }
      catch (const std::exception &) { result = "10010:"; }
    gd::String text(result.c_str());
    gd::get<GDExtensionInterfaceGetVariantFromTypeConstructor>("get_variant_from_type_constructor")(GDEXTENSION_VARIANT_TYPE_STRING)(out, text.data.data());
}

static GDExtensionObjectPtr create(void *) {
    gd::Name parent("RefCounted"), name("InariFmodRuntime");
    auto object = gd::get<GDExtensionInterfaceClassdbConstructObject>("classdb_construct_object")(parent.data.data());
    gd::get<GDExtensionInterfaceObjectSetInstance>("object_set_instance")(object, name.data.data(), new NativeRuntime());
    return object;
}
static void destroy(void *, GDExtensionClassInstancePtr instance) { delete static_cast<NativeRuntime *>(instance); }
static void initialize(void *, GDExtensionInitializationLevel level) {
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    gd::Name name("InariFmodRuntime"), parent("RefCounted"), method("invoke"), empty("");
    gd::String empty_string("");
    GDExtensionClassCreationInfo2 info{};
    info.is_exposed = true; info.create_instance_func = create; info.free_instance_func = destroy;
    gd::get<GDExtensionInterfaceClassdbRegisterExtensionClass2>("classdb_register_extension_class2")(gd::library, name.data.data(), parent.data.data(), &info);
    GDExtensionPropertyInfo returned{};
    returned.type = GDEXTENSION_VARIANT_TYPE_STRING; returned.name = empty.data.data();
    returned.class_name = empty.data.data(); returned.hint_string = empty_string.data.data();
    GDExtensionClassMethodInfo call{};
    call.name = method.data.data(); call.call_func = invoke;
    call.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL | GDEXTENSION_METHOD_FLAG_VARARG;
    call.has_return_value = true; call.return_value_info = &returned;
    gd::get<GDExtensionInterfaceClassdbRegisterExtensionClassMethod>("classdb_register_extension_class_method")(gd::library, name.data.data(), &call);
}
static void deinitialize(void *, GDExtensionInitializationLevel level) {
    if (level == GDEXTENSION_INITIALIZATION_SCENE) {
        gd::Name name("InariFmodRuntime");
        gd::get<GDExtensionInterfaceClassdbUnregisterExtensionClass>("classdb_unregister_extension_class")(gd::library, name.data.data());
    }
}
extern "C" __declspec(dllexport) GDExtensionBool inari_fmod_init(GDExtensionInterfaceGetProcAddress api,
    GDExtensionClassLibraryPtr library, GDExtensionInitialization *init) {
    gd::api = api; gd::library = library;
    init->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    init->initialize = initialize; init->deinitialize = deinitialize;
    return true;
}
