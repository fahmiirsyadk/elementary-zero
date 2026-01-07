namespace ElementaryZero {

    public class RecipeManager : Object {
        private string recipes_dir;

        public RecipeManager () {
            var exec_path = GLib.Environment.get_variable ("ELEMENTARY_ZERO_RECIPES_DIR");
            if (exec_path != null && exec_path != "") {
                recipes_dir = exec_path;
            } else {
                string[] search_paths = {
                    Path.build_filename (Environment.get_current_dir (), "recipes"),
                    Path.build_filename (Environment.get_user_data_dir (), "elementary-zero", "recipes"),
                    "/usr/share/elementary-zero/recipes",
                    "/usr/local/share/elementary-zero/recipes"
                };

                recipes_dir = "";
                foreach (var path in search_paths) {
                    if (File.new_for_path (path).query_exists ()) {
                        recipes_dir = path;
                        break;
                    }
                }

                if (recipes_dir == "") {
                    recipes_dir = Path.build_filename (Environment.get_user_data_dir (), "elementary-zero", "recipes");
                }
            }
        }

        public Gee.ArrayList<Recipe> discover_recipes () {
            var recipes = new Gee.ArrayList<Recipe> ();
            var dir = File.new_for_path (recipes_dir);

            if (!dir.query_exists ()) {
                warning ("Recipes directory does not exist: %s", recipes_dir);
                return recipes;
            }

            try {
                var enumerator = dir.enumerate_children (FileAttribute.STANDARD_NAME,
                                                          FileQueryInfoFlags.NONE);
                FileInfo? info;

                while ((info = enumerator.next_file ()) != null) {
                    if (info.get_file_type () == FileType.DIRECTORY) {
                        var recipe_path = Path.build_filename (recipes_dir, info.get_name ());
                        var recipe_yaml = Path.build_filename (recipe_path, "recipe.yaml");

                        if (File.new_for_path (recipe_yaml).query_exists ()) {
                            var recipe = parse_recipe (info.get_name (), recipe_path);
                            if (recipe != null) {
                                recipes.add (recipe);
                            }
                        }
                    }
                }
            } catch (Error e) {
                warning ("Error discovering recipes: %s", e.message);
            }

            return recipes;
        }

        private Recipe? parse_recipe (string name, string path) {
            var recipe = new Recipe (name, path);
            var yaml_path = Path.build_filename (path, "recipe.yaml");

            try {
                var file = File.new_for_path (yaml_path);
                if (!file.query_exists ()) {
                    return null;
                }

                var contents = new StringBuilder ();
                var dis = new DataInputStream (file.read ());
                string? line;

                while ((line = dis.read_line ()) != null) {
                    contents.append (line).append ("\n");
                }

                var yaml = contents.str;

                recipe.git_url = extract_nested_yaml_value (yaml, "upstream", "git:") ??
                               extract_yaml_value (yaml, "git:");
                recipe.branch = extract_nested_yaml_value (yaml, "upstream", "branch:") ??
                              extract_yaml_value (yaml, "branch:") ?? "master";
                var pinned = extract_nested_yaml_value (yaml, "upstream", "pinned_sha:") ??
                           extract_yaml_value (yaml, "pinned_sha:");
                if (pinned != null && pinned != "") {
                    pinned = pinned.replace ("\"", "").replace ("'", "").strip ();
                    var comment_pos = pinned.index_of ("#");
                    if (comment_pos >= 0) {
                        pinned = pinned.substring (0, comment_pos).strip ();
                    }
                    recipe.pinned_sha = (pinned.length > 0) ? pinned : null;
                } else {
                    recipe.pinned_sha = null;
                }

                var package_name = extract_yaml_value (yaml, "package_name:");
                if (package_name != null && package_name != "") {
                    recipe.package_name = package_name.replace ("\"", "").replace ("'", "").strip ();
                }

                var build_prefix = extract_nested_yaml_value (yaml, "build", "prefix:");
                if (build_prefix != null && build_prefix != "") {
                    recipe.build_prefix = build_prefix.replace ("\"", "").replace ("'", "").strip ();
                }

                var meson_opts = extract_nested_yaml_value (yaml, "build", "meson_options:");
                if (meson_opts != null && meson_opts != "") {
                    recipe.meson_options = meson_opts.replace ("\"", "").replace ("'", "").strip ();
                }

                parse_dependencies (yaml, "dependencies", "build:", recipe.build_dependencies);
                parse_dependencies (yaml, "dependencies", "runtime:", recipe.runtime_dependencies);

                parse_patches (yaml, path, recipe);

                var patches_dir = Path.build_filename (path, "patches");
                var patches_file = File.new_for_path (patches_dir);
                if (patches_file.query_exists ()) {
                    try {
                        var enumerator = patches_file.enumerate_children (FileAttribute.STANDARD_NAME,
                                                                          FileQueryInfoFlags.NONE);
                        FileInfo? info;
                        while ((info = enumerator.next_file ()) != null) {
                            if (info.get_name ().has_suffix (".patch")) {
                                var patch_path = Path.build_filename (patches_dir, info.get_name ());
                                if (!recipe.patches.contains (patch_path)) {
                                    recipe.patches.add (patch_path);
                                }
                            }
                        }
                    } catch (Error e) {
                        warning ("Error reading patches directory: %s", e.message);
                    }
                }

                check_recipe_status (recipe);

                var state_mgr = StateManager.get_default ();
                recipe.is_installed = state_mgr.is_recipe_installed (recipe.name);
                if (recipe.is_installed) {
                    recipe.status = Recipe.RecipeStatus.INSTALLED;
                }

            } catch (Error e) {
                warning ("Error parsing recipe %s: %s", name, e.message);
                return null;
            }

            return recipe;
        }

        private string extract_yaml_value (string yaml, string key) {
            var lines = yaml.split ("\n");
            foreach (var line in lines) {
                var trimmed = line.strip ();
                if (trimmed.has_prefix (key) || trimmed.contains (":" + key)) {
                    var colon_pos = trimmed.index_of (":");
                    if (colon_pos >= 0) {
                        var value = trimmed.substring (colon_pos + 1).strip ();
                        value = value.replace ("\"", "").replace ("'", "");
                        var comment_pos = value.index_of ("#");
                        if (comment_pos >= 0) {
                            value = value.substring (0, comment_pos).strip ();
                        }
                        return value;
                    }
                }
            }
            return "";
        }

        private string? extract_nested_yaml_value (string yaml, string section, string key) {
            var lines = yaml.split ("\n");
            bool in_section = false;
            int section_indent = -1;

            foreach (var line in lines) {
                var trimmed = line.strip ();
                var leading_spaces = line.length - trimmed.length;

                if (!in_section && trimmed.has_prefix (section + ":")) {
                    in_section = true;
                    section_indent = leading_spaces;
                    continue;
                }

                if (in_section && leading_spaces <= section_indent && trimmed.has_suffix (":") &&
                    !trimmed.has_prefix (key)) {
                    break;
                }

                if (in_section && trimmed.has_prefix (key)) {
                    var colon_pos = trimmed.index_of (":");
                    if (colon_pos >= 0) {
                        var value = trimmed.substring (colon_pos + 1).strip ();
                        value = value.replace ("\"", "").replace ("'", "");
                        var comment_pos = value.index_of ("#");
                        if (comment_pos >= 0) {
                            value = value.substring (0, comment_pos).strip ();
                        }
                        return value.length > 0 ? value : null;
                    }
                }
            }

            return null;
        }

        private void parse_dependencies (string yaml, string section, string subsection, Gee.ArrayList<string> dependencies) {
            var lines = yaml.split ("\n");
            bool in_section = false;
            bool in_subsection = false;
            int section_indent = -1;
            int subsection_indent = -1;

            foreach (var line in lines) {
                var trimmed = line.strip ();
                var leading_spaces = line.length - trimmed.length;

                if (!in_section && trimmed.has_prefix (section + ":")) {
                    in_section = true;
                    section_indent = leading_spaces;
                    continue;
                }

                if (in_section && !in_subsection && trimmed.has_prefix (subsection)) {
                    in_subsection = true;
                    subsection_indent = leading_spaces;
                    continue;
                }

                if (in_section && leading_spaces <= section_indent && trimmed.has_suffix (":") &&
                    !trimmed.has_prefix (subsection)) {
                    break;
                }

                if (in_subsection && leading_spaces <= subsection_indent && trimmed.has_suffix (":")) {
                    in_subsection = false;
                    continue;
                }

                if (in_subsection && trimmed.has_prefix ("-")) {
                    var dep = trimmed.substring (1).strip ();
                    dep = dep.replace ("\"", "").replace ("'", "");
                    var comment_pos = dep.index_of ("#");
                    if (comment_pos >= 0) {
                        dep = dep.substring (0, comment_pos).strip ();
                    }
                    if (dep.length > 0) {
                        dependencies.add (dep);
                    }
                }
            }
        }

        private void parse_patches (string yaml, string recipe_path, Recipe recipe) {
            var lines = yaml.split ("\n");
            bool in_patches = false;
            int patches_indent = -1;

            foreach (var line in lines) {
                var trimmed = line.strip ();
                var leading_spaces = line.length - trimmed.length;

                if (!in_patches && trimmed.has_prefix ("patches:")) {
                    in_patches = true;
                    patches_indent = leading_spaces;
                    continue;
                }

                if (in_patches && leading_spaces <= patches_indent && trimmed.has_suffix (":") &&
                    !trimmed.has_prefix ("-")) {
                    break;
                }

                if (in_patches && trimmed.has_prefix ("-")) {
                    if (trimmed.contains ("path:")) {
                        var patch_meta = new Recipe.PatchMetadata ();
                        try {
                            var path_match = new Regex (".*path:\\s*([^\\s]+)");
                            MatchInfo match_info;
                            if (path_match.match (trimmed, 0, out match_info)) {
                                var patch_path = match_info.fetch (1);
                                patch_path = patch_path.replace ("\"", "").replace ("'", "");
                                if (!Path.is_absolute (patch_path)) {
                                    patch_path = Path.build_filename (recipe_path, patch_path);
                                }
                                patch_meta.patch_path = patch_path;
                                recipe.patches.add (patch_path);
                            }
                            var version_match = new Regex (".*compatible_version:\\s*([^\\s]+)");
                            if (version_match.match (trimmed, 0, out match_info)) {
                                patch_meta.compatible_version = match_info.fetch (1).replace ("\"", "").replace ("'", "");
                            }
                            var desc_match = new Regex (".*description:\\s*\"([^\"]+)\"");
                            if (desc_match.match (trimmed, 0, out match_info)) {
                                patch_meta.description = match_info.fetch (1);
                            }
                        } catch (RegexError e) {
                            warning ("Error parsing patch metadata: %s", e.message);
                        }
                        recipe.patch_metadata.add (patch_meta);
                    } else {
                        var patch_path = trimmed.substring (1).strip ();
                        patch_path = patch_path.replace ("\"", "").replace ("'", "");
                        var comment_pos = patch_path.index_of ("#");
                        if (comment_pos >= 0) {
                            patch_path = patch_path.substring (0, comment_pos).strip ();
                        }
                        if (patch_path.length > 0) {
                            if (!Path.is_absolute (patch_path)) {
                                patch_path = Path.build_filename (recipe_path, patch_path);
                            }
                            recipe.patches.add (patch_path);
                        }
                    }
                }
            }
        }

        private void check_recipe_status (Recipe recipe) {
            var build_dir = Path.build_filename (recipe.path, "_work", "src", "build");
            var install_dir = Path.build_filename (recipe.path, "_work", "install");

            if (File.new_for_path (build_dir).query_exists ()) {
                recipe.status = Recipe.RecipeStatus.BUILT;
                try {
                    var build_info = File.new_for_path (build_dir).query_info (
                        FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
                    var time = build_info.get_modification_date_time ();
                    recipe.last_built = new DateTime.from_unix_local (time.to_unix ());
                } catch (Error e) {
                    recipe.last_built = new DateTime.now_local ();
                }
            }
        }
    }
}
