namespace ElementaryZero {

    public class RecipeValidator : Object {
        public signal void validation_progress (string message);

        public class ValidationResult : Object {
            public bool is_valid { get; set; default = false; }
            public Gee.ArrayList<string> errors { get; construct; }
            public Gee.ArrayList<string> warnings { get; construct; }

            public ValidationResult () {
                Object (
                    errors: new Gee.ArrayList<string> (),
                    warnings: new Gee.ArrayList<string> ()
                );
            }
        }

        public async ValidationResult validate_recipe (Recipe recipe) throws Error {
            var result = new ValidationResult ();
            result.is_valid = true;

            validation_progress ("Validating recipe: " + recipe.name);

            var yaml_path = Path.build_filename (recipe.path, "recipe.yaml");
            if (!(yield validate_yaml_schema (yaml_path))) {
                result.errors.add ("YAML schema validation failed");
                result.is_valid = false;
            }

            if (recipe.git_url == null || recipe.git_url == "") {
                result.errors.add ("git_url is required");
                result.is_valid = false;
            }

            if (!(yield validate_patches (recipe.patches))) {
                result.errors.add ("One or more patch files are invalid");
                result.is_valid = false;
            }

            if (recipe.git_url != null && recipe.git_url != "") {
                try {
                    if (!(yield validate_git_repo (recipe.git_url, recipe.branch, recipe.pinned_sha))) {
                        result.warnings.add ("Git repository validation failed - repository may be inaccessible");
                    }
                } catch (Error e) {
                    result.warnings.add ("Git repository validation error: " + e.message);
                }
            }

            try {
                if (!(yield validate_build_environment ())) {
                    result.errors.add ("Build environment validation failed - required tools may be missing");
                    result.is_valid = false;
                }
            } catch (Error e) {
                result.errors.add ("Build environment validation error: " + e.message);
                result.is_valid = false;
            }

            try {
                if (!(yield validate_recipe_dependencies (recipe))) {
                    result.errors.add ("Recipe build dependencies not satisfied - see validation output for details");
                    result.is_valid = false;
                }
            } catch (Error e) {
                result.errors.add ("Dependency validation error: " + e.message);
                result.is_valid = false;
            }

            if (result.is_valid) {
                validation_progress ("Recipe validation passed");
            } else {
                validation_progress ("Recipe validation failed with " + result.errors.size.to_string () + " error(s)");
            }

            return result;
        }

        public async bool validate_yaml_schema (string yaml_path) throws Error {
            var file = File.new_for_path (yaml_path);
            if (!file.query_exists ()) {
                throw new Error (Quark.from_string ("validation"), 1, "YAML file not found: " + yaml_path);
            }

            validation_progress ("Validating YAML schema...");

            try {
                var dis = new DataInputStream (file.read ());
                string? line;
                bool has_content = false;
                bool has_upstream = false;

                while ((line = yield dis.read_line_async ()) != null) {
                    has_content = true;
                    if (line.contains ("upstream:") || line.contains ("git:")) {
                        has_upstream = true;
                    }
                }

                if (!has_content) {
                    validation_progress ("WARNING: YAML file appears empty");
                    return false;
                }

                if (!has_upstream) {
                    validation_progress ("WARNING: YAML file missing upstream configuration");
                    return false;
                }

                return true;
            } catch (Error e) {
                throw new Error (Quark.from_string ("validation"), 1,
                               "Error reading YAML file: " + e.message);
            }
        }

        public async bool validate_patches (Gee.ArrayList<string> patches) throws Error {
            validation_progress ("Validating patch files...");

            foreach (var patch_path in patches) {
                var patch_file = File.new_for_path (patch_path);

                if (!patch_file.query_exists ()) {
                    validation_progress ("ERROR: Patch file not found: " + patch_path);
                    return false;
                }

                try {
                    var info = patch_file.query_info (FileAttribute.ACCESS_CAN_READ, FileQueryInfoFlags.NONE);
                    if (!info.get_attribute_boolean (FileAttribute.ACCESS_CAN_READ)) {
                        validation_progress ("ERROR: Patch file is not readable: " + patch_path);
                        return false;
                    }
                } catch (Error e) {
                    validation_progress ("ERROR: Cannot access patch file: " + patch_path + " - " + e.message);
                    return false;
                }

                try {
                    var dis = new DataInputStream (patch_file.read ());
                    var first_line = yield dis.read_line_async ();

                    if (first_line == null || (!first_line.has_prefix ("---") &&
                                               !first_line.has_prefix ("diff") &&
                                               !first_line.has_prefix ("Index:"))) {
                        validation_progress ("WARNING: Patch file may not be in standard format: " + patch_path);
                    }
                } catch (Error e) {
                    validation_progress ("WARNING: Could not verify patch format: " + patch_path);
                }

                validation_progress ("✓ Validated: " + Path.get_basename (patch_path));
            }

            return true;
        }

        public async bool validate_git_repo (string git_url, string branch, string? sha) throws Error {
            validation_progress ("Validating git repository accessibility...");

            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE |
                                                   SubprocessFlags.STDERR_PIPE);

            try {
                string[] argv = { "git", "ls-remote", "--heads", git_url, branch };
                var process = launcher.spawnv (argv);

                var stdout = process.get_stdout_pipe ();
                var dis = new DataInputStream (stdout);
                var has_branch = false;
                string? line;

                while ((line = yield dis.read_line_async ()) != null) {
                    if (line.contains ("refs/heads/" + branch)) {
                        has_branch = true;
                        break;
                    }
                }

                yield process.wait_async ();

                if (process.get_exit_status () != 0) {
                    validation_progress ("WARNING: Git repository may be inaccessible or branch not found");
                    return false;
                }

                if (!has_branch) {
                    validation_progress ("WARNING: Branch '" + branch + "' not found in repository");
                    return false;
                }

                if (sha != null && sha != "") {
                    var clean_sha = sha.replace ("\"", "").replace ("'", "").strip ();
                    string[] sha_argv = { "git", "ls-remote", git_url, clean_sha };
                    process = launcher.spawnv (sha_argv);

                    yield process.wait_async ();

                    if (process.get_exit_status () != 0) {
                        validation_progress ("WARNING: Pinned SHA '" + clean_sha.substring (0, 7) + "' not found in repository");
                        return false;
                    }
                }

                validation_progress ("✓ Git repository validated");
                return true;
            } catch (Error e) {
                validation_progress ("WARNING: Git repository validation failed: " + e.message);
                return false;
            }
        }

        public async bool validate_build_environment () throws Error {
            validation_progress ("Validating build environment...");

            string[] required_tools = { "git", "meson", "ninja" };

            foreach (var tool in required_tools) {
                var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);

                try {
                    var process = launcher.spawnv (new string[] { "which", tool });
                    yield process.wait_async ();

                    if (process.get_exit_status () != 0) {
                        validation_progress ("ERROR: Required tool not found: " + tool);
                        return false;
                    }
                    validation_progress ("✓ Found: " + tool);
                } catch (Error e) {
                    validation_progress ("ERROR: Cannot check for tool " + tool + ": " + e.message);
                    return false;
                }
            }

            var tmp_dir = Environment.get_tmp_dir ();
            var test_file = File.new_for_path (Path.build_filename (tmp_dir, ".elementary-zero-test"));
            try {
                test_file.create (FileCreateFlags.NONE, null);
                test_file.delete (null);
                validation_progress ("✓ Disk space check passed");
            } catch (Error e) {
                validation_progress ("WARNING: Cannot write to temporary directory: " + e.message);
            }

            validation_progress ("✓ Build environment validated");
            return true;
        }

        public async bool validate_recipe_dependencies (Recipe recipe) throws Error {
            if (recipe.build_dependencies.size == 0) {
                return true;
            }

            validation_progress ("Checking recipe build dependencies...");
            var missing = yield check_package_dependencies (recipe.build_dependencies);

            if (missing.size > 0) {
                validation_progress ("ERROR: Missing build dependencies:");
                foreach (var pkg in missing) {
                    validation_progress ("  - " + pkg);
                }
                return false;
            }

            validation_progress ("✓ All build dependencies satisfied");
            return true;
        }

        private async Gee.ArrayList<string> check_package_dependencies (Gee.ArrayList<string> dependencies) throws Error {
            var missing = new Gee.ArrayList<string> ();
            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE |
                                                   SubprocessFlags.STDERR_PIPE);

            foreach (var dep in dependencies) {
                bool found = false;

                try {
                    var process = launcher.spawnv (new string[] {
                        "dpkg", "-l", dep
                    });
                    yield process.wait_async ();

                    if (process.get_exit_status () == 0) {
                        var stdout = process.get_stdout_pipe ();
                        if (stdout != null) {
                            var dis = new DataInputStream (stdout);
                            string? line;
                            while ((line = yield dis.read_line_async ()) != null) {
                                if (line.has_prefix ("ii") && line.contains (dep)) {
                                    found = true;
                                    validation_progress ("✓ Found: " + dep);
                                    break;
                                }
                            }
                        }
                    }
                } catch (Error e) {
                }

                if (found) {
                    continue;
                }

                try {
                    var process = launcher.spawnv (new string[] {
                        "pkg-config", "--exists", dep
                    });
                    yield process.wait_async ();

                    if (process.get_exit_status () == 0) {
                        validation_progress ("✓ Found: " + dep + " (via pkg-config)");
                        continue;
                    }
                } catch (Error e) {
                }

                try {
                    var process = launcher.spawnv (new string[] {
                        "which", dep
                    });
                    yield process.wait_async ();

                    if (process.get_exit_status () == 0) {
                        validation_progress ("✓ Found: " + dep + " (command)");
                        continue;
                    }
                } catch (Error e) {
                }

                missing.add (dep);
                validation_progress ("✗ Missing: " + dep);
            }

            return missing;
        }
    }
}
