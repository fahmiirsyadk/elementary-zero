namespace ElementaryZero {

    public class StateManager : Object {
        private static StateManager? instance = null;
        private string state_file_path;
        private Json.Object state_data;

        public static StateManager get_default () {
            if (instance == null) {
                instance = new StateManager ();
            }
            return instance;
        }

        private StateManager () {
            var config_dir = Path.build_filename (Environment.get_user_config_dir (), "elementary-zero");
            var config_file = File.new_for_path (config_dir);
            try {
                if (!config_file.query_exists ()) {
                    config_file.make_directory_with_parents (null);
                }
            } catch (Error e) {
                warning ("Failed to create config directory: %s", e.message);
            }

            state_file_path = Path.build_filename (config_dir, "state.json");
            state_data = new Json.Object ();

            load_state ();
        }

        private void load_state () {
            var file = File.new_for_path (state_file_path);
            if (!file.query_exists ()) {
                return;
            }

            try {
                var parser = new Json.Parser ();
                parser.load_from_file (state_file_path);
                var root = parser.get_root ();
                if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
                    state_data = root.get_object ();
                }
            } catch (Error e) {
                warning ("Failed to load state: %s", e.message);
            }
        }

        private void save_state () {
            try {
                var generator = new Json.Generator ();
                generator.pretty = true;
                generator.indent = 2;
                var root = new Json.Node (Json.NodeType.OBJECT);
                root.set_object (state_data);
                generator.set_root (root);

                generator.to_file (state_file_path);
            } catch (Error e) {
                warning ("Failed to save state: %s", e.message);
            }
        }

        public bool is_recipe_installed (string recipe_name) {
            if (!state_data.has_member (recipe_name)) {
                return false;
            }

            var recipe_obj = state_data.get_object_member (recipe_name);
            if (recipe_obj.has_member ("installed")) {
                return recipe_obj.get_boolean_member ("installed");
            }

            return false;
        }

        public void set_recipe_installed (string recipe_name, bool installed) {
            Json.Object recipe_obj;
            if (state_data.has_member (recipe_name)) {
                recipe_obj = state_data.get_object_member (recipe_name);
            } else {
                recipe_obj = new Json.Object ();
                state_data.set_object_member (recipe_name, recipe_obj);
            }

            recipe_obj.set_boolean_member ("installed", installed);
            if (installed) {
                var now = new DateTime.now_utc ();
                recipe_obj.set_string_member ("installed_at", now.format_iso8601 ());
            }

            save_state ();
        }

        public string? get_installed_version (string recipe_name) {
            if (!state_data.has_member (recipe_name)) {
                return null;
            }

            var recipe_obj = state_data.get_object_member (recipe_name);
            if (recipe_obj.has_member ("version")) {
                return recipe_obj.get_string_member ("version");
            }

            return null;
        }

        public void set_installed_version (string recipe_name, string version) {
            Json.Object recipe_obj;
            if (state_data.has_member (recipe_name)) {
                recipe_obj = state_data.get_object_member (recipe_name);
            } else {
                recipe_obj = new Json.Object ();
                state_data.set_object_member (recipe_name, recipe_obj);
            }

            recipe_obj.set_string_member ("version", version);
            save_state ();
        }
    }
}
