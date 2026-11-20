// VagnFast: the game's hot loops in C++ (GDExtension). One engine singleton,
// "VagnFast"; GDScript checks Engine.has_singleton("VagnFast") and keeps its own
// code as the fallback, so the game runs without the library.
#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/godot.hpp>

#include "vagn_fast.h"

using namespace godot;

static VagnFast *singleton = nullptr;

void initialize_vagnfast(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(VagnFast);
	singleton = memnew(VagnFast);
	Engine::get_singleton()->register_singleton("VagnFast", singleton);
}

void uninitialize_vagnfast(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	Engine::get_singleton()->unregister_singleton("VagnFast");
	memdelete(singleton);
	singleton = nullptr;
}

extern "C" {
GDExtensionBool GDE_EXPORT vagnfast_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_vagnfast);
	init_obj.register_terminator(uninitialize_vagnfast);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
