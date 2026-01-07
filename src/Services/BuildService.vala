namespace ElementaryZero {

    public class BuildService : Object {
        public signal void build_progress (string message);
        public signal void build_complete (bool success, string? error);
        public signal void build_progress_percent (double percent);

        private Subprocess? current_process;
        private Recipe? current_recipe;
        private Gee.ArrayList<string> enabled_patches;
        private PatchService patch_service;
        private string? checkpoint_dir;

        construct {
            patch_service = new PatchService ();
        }

        public async void build_recipe (Recipe recipe, Gee.ArrayList<string>? patches_to_apply = null) {
            recipe.status = Recipe.RecipeStatus.BUILDING;
            current_recipe = recipe;

            if (patches_to_apply != null) {
                enabled_patches = patches_to_apply;
            } else {
                enabled_patches = recipe.patches;
            }

            try {

                build_progress ("Validating build environment...");
                build_progress_percent (0.0);
                if (!(yield validate_build_environment ())) {
                    throw new Error (Quark.from_string ("build"), 1, "Build environment validation failed");
                }

                build_progress ("Step 1/5: Getting fresh source repository...");
                build_progress_percent (0.1);
                yield get_fresh_source (recipe);

                yield create_checkpoint (recipe);
                build_progress_percent (0.2);

                build_progress ("Step 2/5: Checking diff against repository...");
                yield check_diff (recipe);
                build_progress_percent (0.3);

                build_progress ("Step 3/5: Applying patches...");
                yield apply_patches (recipe);
                build_progress_percent (0.5);

                build_progress ("Step 4/5: Building package...");
                yield build_package (recipe);
                build_progress_percent (0.9);

                build_progress ("Step 5/5: Verifying build...");
                yield verify_build (recipe);
                build_progress_percent (1.0);

                yield cleanup_checkpoint (recipe);

                recipe.status = Recipe.RecipeStatus.BUILT;
                recipe.last_built = new DateTime.now_local ();
                build_progress ("Done. Build completed successfully.");
                build_complete (true, null);

            } catch (Error e) {

                recipe.status = Recipe.RecipeStatus.BUILD_FAILED;
                recipe.build_error = e.message;
                build_progress ("");
                build_progress ("ERROR: Build failed - " + e.message);

                try {
                    build_progress ("Attempting to restore from checkpoint...");
                    yield restore_checkpoint (recipe);
                    build_progress ("Checkpoint restored. Work directory cleaned.");
                } catch (Error restore_error) {

                    build_progress ("Checkpoint restore failed, performing cleanup...");
                    try {
                        yield cleanup_failed_build (recipe);
                    } catch (Error cleanup_error) {

                        warning ("Error during cleanup: %s", cleanup_error.message);
                    }
                }

                build_progress ("Build process stopped.");
                build_complete (false, e.message);
            } finally {
                current_process = null;
                current_recipe = null;
                checkpoint_dir = null;
            }
        }

        private async void get_fresh_source (Recipe recipe) throws Error {
            var workdir = Path.build_filename (recipe.path, "_work");
            var src_dir = Path.build_filename (workdir, "src");

            var workdir_file = File.new_for_path (workdir);
            if (workdir_file.query_exists ()) {
                try {

                    var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE |
                                                            SubprocessFlags.STDERR_MERGE);
                    launcher.set_cwd (recipe.path);
                    current_process = launcher.spawnv (new string[] {
                        "rm", "-rf", workdir
                    });
                    yield current_process.wait_async ();
                } catch (Error e) {

                }
            }

            var src_dir_file = File.new_for_path (src_dir);
            if (!src_dir_file.query_exists ()) {
                src_dir_file.make_directory_with_parents (null);
            }

            var git_dir = Path.build_filename (src_dir, ".git");
            var git_dir_file = File.new_for_path (git_dir);

            if (!git_dir_file.query_exists ()) {
                build_progress ("Cloning repository: " + recipe.git_url);
                var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE |
                                                        SubprocessFlags.STDERR_MERGE);
                launcher.set_cwd (recipe.path);
                current_process = launcher.spawnv (new string[] {
                    "git", "clone", recipe.git_url, src_dir
                });

                var stdout = current_process.get_stdout_pipe ();
                var dis = new DataInputStream (stdout);
                string? line;
                while ((line = yield dis.read_line_async ()) != null) {
                    build_progress (line);
                }

                yield current_process.wait_async ();
                if (current_process.get_exit_status () != 0) {
                    throw new Error (Quark.from_string ("build"), 1, "Failed to clone repository");
                }
            } else {
                build_progress ("Fetching latest changes...");
                var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE |
                                                        SubprocessFlags.STDERR_MERGE);
                launcher.set_cwd (src_dir);
                current_process = launcher.spawnv (new string[] {
                    "git", "fetch", "origin", recipe.branch
                });

                yield current_process.wait_async ();
                if (current_process.get_exit_status () != 0) {
                    throw new Error (Quark.from_string ("build"), 1, "Failed to fetch repository");
                }
            }

            build_progress ("Checking out " + recipe.branch + "...");
            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE |
                                                    SubprocessFlags.STDERR_MERGE);
            launcher.set_cwd (src_dir);

            current_process = launcher.spawnv (new string[] {
                "git", "checkout", recipe.branch
            });

            yield current_process.wait_async ();
            if (current_process.get_exit_status () != 0) {
                throw new Error (Quark.from_string ("build"), 1, "Failed to checkout branch");
            }

            current_process = launcher.spawnv (new string[] {
                "git", "pull", "--ff-only", "origin", recipe.branch
            });

            yield current_process.wait_async ();

            if (recipe.pinned_sha != null && recipe.pinned_sha != "" &&
                recipe.pinned_sha != "\"\"" && recipe.pinned_sha != "''") {
                var clean_sha = recipe.pinned_sha.replace ("\"", "").replace ("'", "").strip ();
                build_progress ("Checking out pinned commit: " + clean_sha.substring (0, 7));
                current_process = launcher.spawnv (new string[] {
                    "git", "checkout", clean_sha
                });

                yield current_process.wait_async ();
                if (current_process.get_exit_status () != 0) {
                    throw new Error (Quark.from_string ("build"), 1, "Failed to checkout pinned SHA");
                }
            }

            current_process = launcher.spawnv (new string[] {
                "git", "reset", "--hard", "HEAD"
            });
            yield current_process.wait_async ();

            current_process = launcher.spawnv (new string[] {
                "git", "clean", "-fdx"
            });
            yield current_process.wait_async ();
        }

        private async void check_diff (Recipe recipe) throws Error {
            var src_dir = Path.build_filename (recipe.path, "_work", "src");

            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE |
                                                    SubprocessFlags.STDERR_MERGE);
            launcher.set_cwd (src_dir);

            current_process = launcher.spawnv (new string[] {
                "git", "status", "--porcelain"
            });

            var stdout = current_process.get_stdout_pipe ();
            var dis = new DataInputStream (stdout);
            string? line;
            var has_changes = false;

            while ((line = yield dis.read_line_async ()) != null) {
                if (line.strip ().length > 0) {
                    has_changes = true;
                    break;
                }
            }

            yield current_process.wait_async ();

            if (has_changes) {
                build_progress ("Repository has uncommitted changes, cleaning...");
                current_process = launcher.spawnv (new string[] {
                    "git", "reset", "--hard", "HEAD"
                });
                yield current_process.wait_async ();

                current_process = launcher.spawnv (new string[] {
                    "git", "clean", "-fdx"
                });
                yield current_process.wait_async ();
            } else {
                build_progress ("Repository is clean, ready for patching.");
            }
        }

        private async void apply_patches (Recipe recipe) throws Error {
            var src_dir = Path.build_filename (recipe.path, "_work", "src");
            var patches_dir = Path.build_filename (recipe.path, "patches");

            if (enabled_patches.size == 0) {
                build_progress ("No patches to apply.");
                return;
            }

            build_progress ("Applying " + enabled_patches.size.to_string () + " patch(es)...");

            int patch_index = 0;
            foreach (var patch_path in enabled_patches) {
                patch_index++;

                string absolute_patch_path;
                if (Path.is_absolute (patch_path)) {
                    absolute_patch_path = patch_path;
                } else {
                    absolute_patch_path = Path.build_filename (recipe.path, patch_path);
                }

                var patch_file = File.new_for_path (absolute_patch_path);
                if (!patch_file.query_exists ()) {
                    throw new Error (Quark.from_string ("build"), 1,
                                   "Patch file not found: " + patch_path);
                }

                var patch_name = Path.get_basename (patch_path);
                build_progress ("[" + patch_index.to_string () + "/" + enabled_patches.size.to_string () +
                              "] Validating patch: " + patch_name);

                var validation_result = yield patch_service.validate_patch (absolute_patch_path, src_dir);

                if (!validation_result.success) {
                    var error_msg = new StringBuilder ();
                    error_msg.append ("Patch validation failed: ").append (patch_name).append ("\n");
                    error_msg.append (validation_result.error_message ?? "Unknown validation error");

                    if (validation_result.conflicted_files.size > 0) {
                        error_msg.append ("\nConflicted files:\n");
                        foreach (var conflicted in validation_result.conflicted_files) {
                            error_msg.append ("  - ").append (conflicted).append ("\n");
                        }
                    }

                    if (validation_result.requires_rebase) {
                        error_msg.append ("\nThis patch may require rebasing. Try updating pinned_sha in recipe.yaml");
                    }

                    throw new Error (Quark.from_string ("build"), 1, error_msg.str);
                }

                build_progress ("[" + patch_index.to_string () + "/" + enabled_patches.size.to_string () +
                              "] Applying patch: " + patch_name);

                var apply_result = yield patch_service.apply_patch (absolute_patch_path, src_dir);

                if (!apply_result.success) {
                    var error_msg = new StringBuilder ();
                    error_msg.append ("Failed to apply patch: ").append (patch_name).append ("\n");
                    error_msg.append (apply_result.error_message ?? "Unknown application error");

                    if (apply_result.conflicted_files.size > 0) {
                        error_msg.append ("\nConflicted files:\n");
                        foreach (var conflicted in apply_result.conflicted_files) {
                            error_msg.append ("  - ").append (conflicted).append ("\n");
                        }
                        error_msg.append ("\nYou may need to manually resolve conflicts or update the patch.");
                    }

                    throw new Error (Quark.from_string ("build"), 1, error_msg.str);
                }

                build_progress ("✓ Patch applied: " + patch_name);

                var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
                launcher.set_cwd (src_dir);
                current_process = launcher.spawnv (new string[] {
                    "git", "status", "--porcelain"
                });
                var stdout = current_process.get_stdout_pipe ();
                var dis = new DataInputStream (stdout);
                string? line;
                var modified_files = new Gee.ArrayList<string> ();
                while ((line = yield dis.read_line_async ()) != null) {
                    if (line.strip ().length > 0 && line.has_prefix ("M")) {
                        var file = line.substring (2).strip ();
                        if (file.length > 0) {
                            modified_files.add (file);
                        }
                    }
                }
                yield current_process.wait_async ();

                if (modified_files.size > 0) {
                    build_progress ("  → Modified " + modified_files.size.to_string () + " file(s)");
                }
            }

            build_progress ("All patches applied successfully.");
        }

        private async void build_package (Recipe recipe) throws Error {
            var src_dir = Path.build_filename (recipe.path, "_work", "src");
            var build_dir = Path.build_filename (src_dir, "build");

            build_progress ("Verifying patches are applied...");
            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE |
                                                    SubprocessFlags.STDERR_MERGE);
            launcher.set_cwd (src_dir);

            current_process = launcher.spawnv (new string[] {
                "git", "status", "--porcelain"
            });

            var stdout = current_process.get_stdout_pipe ();
            var dis = new DataInputStream (stdout);
            string? line;
            var modified_count = 0;
            while ((line = yield dis.read_line_async ()) != null) {
                if (line.strip ().length > 0 && line.has_prefix ("M")) {
                    modified_count++;
                }
            }
            yield current_process.wait_async ();

            if (modified_count > 0) {
                build_progress ("Verified: " + modified_count.to_string () + " file(s) modified by patches");
            } else {
                build_progress ("WARNING: No modified files detected - patches may not have been applied");
            }

            build_progress ("Configuring with Meson...");
            var build_dir_file = File.new_for_path (build_dir);
            if (build_dir_file.query_exists ()) {
                try {

                    var rm_launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE |
                                                               SubprocessFlags.STDERR_MERGE);
                    rm_launcher.set_cwd (recipe.path);
                    current_process = rm_launcher.spawnv (new string[] {
                        "rm", "-rf", build_dir
                    });
                    yield current_process.wait_async ();
                } catch (Error e) {

                }
            }

            var prefix = recipe.build_prefix ?? "/usr";
            var meson_cmd = new Gee.ArrayList<string> ();
            meson_cmd.add ("meson");
            meson_cmd.add ("setup");
            meson_cmd.add (build_dir);
            meson_cmd.add ("--prefix=" + prefix);

            if (recipe.meson_options != null && recipe.meson_options != "") {

                var options = recipe.meson_options.split (" ");
                foreach (var opt in options) {
                    if (opt.strip ().length > 0) {
                        meson_cmd.add (opt.strip ());
                    }
                }
            }

            current_process = launcher.spawnv (meson_cmd.to_array ());

            stdout = current_process.get_stdout_pipe ();
            dis = new DataInputStream (stdout);
            while ((line = yield dis.read_line_async ()) != null) {
                build_progress (line);
            }

            yield current_process.wait_async ();
            if (current_process.get_exit_status () != 0) {
                throw new Error (Quark.from_string ("build"), 1, "Meson configuration failed");
            }

            build_progress ("Compiling with Ninja...");
            current_process = launcher.spawnv (new string[] {
                "ninja", "-C", build_dir
            });

            stdout = current_process.get_stdout_pipe ();
            dis = new DataInputStream (stdout);
            while ((line = yield dis.read_line_async ()) != null) {
                build_progress (line);
            }

            yield current_process.wait_async ();
            if (current_process.get_exit_status () != 0) {
                throw new Error (Quark.from_string ("build"), 1, "Ninja compilation failed");
            }

            build_progress ("Build completed with patched source files.");
        }

        private async void verify_build (Recipe recipe) throws Error {
            var build_dir = Path.build_filename (recipe.path, "_work", "src", "build");
            var build_dir_file = File.new_for_path (build_dir);

            if (!build_dir_file.query_exists ()) {
                throw new Error (Quark.from_string ("build"), 1, "Build directory not found");
            }

            var state_mgr = StateManager.get_default ();
            var now = new DateTime.now_utc ();
            state_mgr.set_installed_version (recipe.name, now.format ("%Y-%m-%dT%H:%M:%SZ"));

            build_progress ("Build verified and status saved.");
        }

        private async bool validate_build_environment () throws Error {

            string[] required_tools = { "git", "meson", "ninja" };

            foreach (var tool in required_tools) {
                var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
                try {
                    current_process = launcher.spawnv (new string[] { "which", tool });
                    yield current_process.wait_async ();
                    if (current_process.get_exit_status () != 0) {
                        throw new Error (Quark.from_string ("build"), 1,
                                       "Required tool not found: " + tool + "\n" +
                                       "Install it with: sudo apt install " + get_package_name_for_tool (tool));
                    }
                    build_progress ("Found: " + tool);
                } catch (Error e) {
                    if (e.code == 1) {
                        throw new Error (Quark.from_string ("build"), 1,
                                       "Required tool not found: " + tool + "\n" +
                                       "Install it with: sudo apt install " + get_package_name_for_tool (tool));
                    }
                    throw e;
                }
            }

            if (current_recipe != null && current_recipe.build_dependencies.size > 0) {
                build_progress ("Checking build dependencies...");
                var missing = yield check_package_dependencies (current_recipe.build_dependencies);
                if (missing.size > 0) {
                    var error_msg = new StringBuilder ();
                    error_msg.append ("Missing build dependencies:\n");
                    foreach (var pkg in missing) {
                        error_msg.append ("  - ").append (pkg).append ("\n");
                    }
                    error_msg.append ("\nInstall them with:\n");
                    error_msg.append ("sudo apt install ");
                    foreach (var pkg in missing) {
                        error_msg.append (pkg).append (" ");
                    }
                    throw new Error (Quark.from_string ("build"), 1, error_msg.str);
                }
                build_progress ("All build dependencies satisfied.");
            }

            return true;
        }

        private string get_package_name_for_tool (string tool) {

            var tool_to_package = new Gee.HashMap<string, string> ();
            tool_to_package["git"] = "git";
            tool_to_package["meson"] = "meson";
            tool_to_package["ninja"] = "ninja-build";
            tool_to_package["valac"] = "valac";

            return tool_to_package.has_key (tool) ? tool_to_package[tool] : tool;
        }

        private async Gee.ArrayList<string> check_package_dependencies (Gee.ArrayList<string> dependencies) throws Error {
            var missing = new Gee.ArrayList<string> ();
            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE |
                                                   SubprocessFlags.STDERR_PIPE);

            foreach (var dep in dependencies) {

                try {
                    current_process = launcher.spawnv (new string[] {
                        "dpkg", "-l", dep
                    });
                    yield current_process.wait_async ();

                    if (current_process.get_exit_status () == 0) {

                        var stdout = current_process.get_stdout_pipe ();
                        if (stdout != null) {
                            var dis = new DataInputStream (stdout);
                            string? line;
                            bool found = false;
                            while ((line = yield dis.read_line_async ()) != null) {

                                if (line.has_prefix ("ii") && line.contains (dep)) {
                                    found = true;
                                    build_progress ("✓ Found: " + dep);
                                    break;
                                }
                            }
                            if (found) {
                                continue;
                            }
                        }
                    }
                } catch (Error e) {

                }

                try {
                    current_process = launcher.spawnv (new string[] {
                        "pkg-config", "--exists", dep
                    });
                    yield current_process.wait_async ();

                    if (current_process.get_exit_status () == 0) {
                        build_progress ("✓ Found: " + dep + " (via pkg-config)");
                        continue;
                    }
                } catch (Error e) {

                }

                try {
                    current_process = launcher.spawnv (new string[] {
                        "which", dep
                    });
                    yield current_process.wait_async ();

                    if (current_process.get_exit_status () == 0) {
                        build_progress ("✓ Found: " + dep + " (command)");
                        continue;
                    }
                } catch (Error e) {

                }

                missing.add (dep);
                build_progress ("✗ Missing: " + dep);
            }

            return missing;
        }

        private async void create_checkpoint (Recipe recipe) throws Error {
            var workdir = Path.build_filename (recipe.path, "_work");
            var checkpoint_base = Path.build_filename (recipe.path, "_checkpoints");

            var checkpoint_base_file = File.new_for_path (checkpoint_base);
            if (!checkpoint_base_file.query_exists ()) {
                checkpoint_base_file.make_directory_with_parents (null);
            }

            var timestamp = new DateTime.now_local ().format ("%Y%m%d_%H%M%S");
            checkpoint_dir = Path.build_filename (checkpoint_base, "checkpoint_" + timestamp);
            var checkpoint_dir_file = File.new_for_path (checkpoint_dir);

            if (checkpoint_dir_file.query_exists ()) {

                var rm_launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
                rm_launcher.set_cwd (recipe.path);
                current_process = rm_launcher.spawnv (new string[] {
                    "rm", "-rf", checkpoint_dir
                });
                yield current_process.wait_async ();
            }

            var workdir_file = File.new_for_path (workdir);
            if (workdir_file.query_exists ()) {
                var cp_launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
                cp_launcher.set_cwd (recipe.path);
                current_process = cp_launcher.spawnv (new string[] {
                    "cp", "-r", workdir, checkpoint_dir
                });
                yield current_process.wait_async ();
                if (current_process.get_exit_status () != 0) {
                    throw new Error (Quark.from_string ("build"), 1, "Failed to create checkpoint");
                }
                build_progress ("Checkpoint created: " + Path.get_basename (checkpoint_dir));
            }
        }

        private async void restore_checkpoint (Recipe recipe) throws Error {
            if (checkpoint_dir == null || checkpoint_dir == "") {

                yield cleanup_failed_build (recipe);
                return;
            }

            var workdir = Path.build_filename (recipe.path, "_work");
            var checkpoint_dir_file = File.new_for_path (checkpoint_dir);

            if (!checkpoint_dir_file.query_exists ()) {

                yield cleanup_failed_build (recipe);
                return;
            }

            var workdir_file = File.new_for_path (workdir);
            if (workdir_file.query_exists ()) {
                var rm_launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
                rm_launcher.set_cwd (recipe.path);
                current_process = rm_launcher.spawnv (new string[] {
                    "rm", "-rf", workdir
                });
                yield current_process.wait_async ();
            }

            var cp_launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
            cp_launcher.set_cwd (recipe.path);
            current_process = cp_launcher.spawnv (new string[] {
                "cp", "-r", checkpoint_dir, workdir
            });
            yield current_process.wait_async ();
            if (current_process.get_exit_status () != 0) {
                throw new Error (Quark.from_string ("build"), 1, "Failed to restore checkpoint");
            }
        }

        private async void cleanup_checkpoint (Recipe recipe) throws Error {
            if (checkpoint_dir == null || checkpoint_dir == "") {
                return;
            }

            var checkpoint_dir_file = File.new_for_path (checkpoint_dir);
            if (checkpoint_dir_file.query_exists ()) {
                var rm_launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
                rm_launcher.set_cwd (recipe.path);
                current_process = rm_launcher.spawnv (new string[] {
                    "rm", "-rf", checkpoint_dir
                });
                yield current_process.wait_async ();

            }
        }

        private async void cleanup_failed_build (Recipe recipe) throws Error {
            var workdir = Path.build_filename (recipe.path, "_work");
            var workdir_file = File.new_for_path (workdir);

            if (workdir_file.query_exists ()) {
                build_progress ("Cleaning up failed build...");
                var rm_launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
                rm_launcher.set_cwd (recipe.path);
                try {
                    current_process = rm_launcher.spawnv (new string[] {
                        "rm", "-rf", workdir
                    });
                    yield current_process.wait_async ();

                } catch (Error e) {

                    warning ("Error cleaning up build directory: %s", e.message);
                } finally {

                    current_process = null;
                }
            }
        }

        public void cancel_build () {
            if (current_process != null) {
                try {
                    current_process.force_exit ();
                } catch (Error e) {
                    warning ("Error canceling build: %s", e.message);
                }
            }
            if (patch_service != null) {
                patch_service.cancel_patch_operation ();
            }
        }
    }
}
